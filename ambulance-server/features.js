'use strict';
// Version 5 features (hackathon edition):
//   - OTP login routes                      (auth.js)
//   - Auto BEST hospital (ETA + ICU + oxygen + doctor + specialty match)
//   - In-transit patient vitals + tele-triage (RED / YELLOW / GREEN) streamed to the hospital ER
//   - Smart roads: pothole crowdsourcing, railway gate status, narrow lanes (roads.js)
//   - Green corridor signal simulation along the route
//   - Offline mode: batch upload of GPS points saved while the network was gone
//   - Push alerts when the app is closed (ntfy push + in-app background service)
//   - Admin live map data + response-time report
//   - Public SOS (citizen) -> nearest ambulance accepts
//   - One-click DEMO simulator for judges
const path = require('path');
const crypto = require('crypto');
const { haversine } = require('./geo');

const r6 = (n) => Math.round(n * 1e6) / 1e6;
const now = () => Date.now();
const txt = (v, n) => (typeof v === 'string' ? v.replace(/[\u0000-\u001f<>]/g, ' ').trim().slice(0, n) : '');
const num = (v, min, max) => { const n = Number(v); return Number.isFinite(n) && n >= min && n <= max ? Math.round(n * 10) / 10 : null; };

// ======================================================================= vitals + triage
const vitalsByTrip = new Map(); // tripId -> [records] (newest last, max 120)

function triage(v) {
  const red = [], yellow = [];
  if (v.spo2 != null) { if (v.spo2 < 90) red.push('SpO2 ' + v.spo2 + '%'); else if (v.spo2 < 94) yellow.push('SpO2 ' + v.spo2 + '%'); }
  if (v.hr != null) { if (v.hr > 130 || v.hr < 45) red.push('Heart rate ' + v.hr); else if (v.hr > 110 || v.hr < 55) yellow.push('Heart rate ' + v.hr); }
  if (v.bpSys != null) { if (v.bpSys < 90) red.push('Low BP ' + v.bpSys); else if (v.bpSys > 180) yellow.push('High BP ' + v.bpSys); }
  if (v.rr != null) { if (v.rr > 30 || v.rr < 8) red.push('Breathing ' + v.rr + '/min'); else if (v.rr > 24) yellow.push('Breathing ' + v.rr + '/min'); }
  if (v.gcs != null) { if (v.gcs <= 8) red.push('GCS ' + v.gcs + ' (unconscious)'); else if (v.gcs <= 12) yellow.push('GCS ' + v.gcs); }
  if (v.temp != null && (v.temp >= 39.5 || v.temp < 35)) yellow.push('Temp ' + v.temp + '°C');
  if (v.ecg === 'stemi') red.push('ECG: STEMI (heart attack)');
  else if (v.ecg === 'vt_vf') red.push('ECG: VT / VF');
  else if (v.ecg === 'afib') yellow.push('ECG: AFib');
  const level = red.length ? 'red' : yellow.length ? 'yellow' : 'green';
  return { level, flags: red.concat(yellow) };
}

function cleanVitals(b, source) {
  const v = {
    hr: num(b.hr, 20, 260), spo2: num(b.spo2, 40, 100),
    bpSys: num(b.bpSys, 40, 280), bpDia: num(b.bpDia, 20, 180),
    rr: num(b.rr, 2, 70), temp: num(b.temp, 30, 44), gcs: num(b.gcs, 3, 15),
    sugar: num(b.sugar, 20, 700),
    ecg: ['normal', 'stemi', 'afib', 'vt_vf', 'other'].includes(b.ecg) ? b.ecg : null,
    note: txt(b.note, 160), source: source || 'app', at: now(),
  };
  v.triage = triage(v);
  return v;
}
function latestVitals(tripId) {
  const list = vitalsByTrip.get(tripId);
  return list && list.length ? list[list.length - 1] : null;
}

// ======================================================================= best hospital
const NEEDS = {
  cardiac: { spec: ['cardiac'], icu: true, vent: false, blood: false, label: 'Cardiac (heart attack)' },
  stroke: { spec: ['stroke', 'neuro'], icu: true, vent: false, blood: false, label: 'Stroke / brain' },
  trauma: { spec: ['trauma'], icu: true, vent: true, blood: true, label: 'Trauma / accident' },
  burn: { spec: ['burn'], icu: true, vent: true, blood: true, label: 'Burn' },
  pediatric: { spec: ['pediatric'], icu: false, vent: false, blood: false, label: 'Child' },
  maternity: { spec: ['maternity'], icu: false, vent: false, blood: true, label: 'Pregnancy / delivery' },
  general: { spec: [], icu: false, vent: false, blood: false, label: 'General' },
};

function rankHospitals(hospitalsMod, near, type, critical) {
  const need = NEEDS[type] || NEEDS.general;
  const list = hospitalsMod.live(near);
  const out = list.map((h) => {
    const reasons = [], warnings = [];
    const distKm = (h.distance || 0) / 1000;
    const etaMin = Math.max(1, Math.round((distKm * 1.3) / 0.55)); // ~33 km/h city average with siren
    let score = 100 - etaMin * 1.6;
    const specs = Array.isArray(h.specialties) ? h.specialties : [];
    if (need.spec.length) {
      if (need.spec.some((s) => specs.includes(s))) { reasons.push(need.label + ' team on duty'); score += 8; } else { warnings.push('No ' + need.label.toLowerCase() + ' specialist'); score -= 35; }
    }
    if (h.icuAvailable > 0) { reasons.push(h.icuAvailable + ' ICU bed free'); score += Math.min(5, h.icuAvailable); } else { warnings.push('ICU full'); score -= need.icu || critical ? 40 : 10; }
    if (h.oxygenLevel === 'none' || !h.oxygenAvailable) { warnings.push('No oxygen'); score -= 40; } else if (h.oxygenLevel === 'low') { warnings.push('Oxygen LOW'); score -= 12; } else reasons.push('Oxygen OK');
    if (!h.emergencyDoctor) { warnings.push('No emergency doctor'); score -= 30; } else reasons.push('Emergency doctor');
    if (need.vent) { if (h.ventilatorsAvailable > 0) reasons.push(h.ventilatorsAvailable + ' ventilator'); else { warnings.push('No ventilator'); score -= 15; } }
    if (need.blood) { if (h.bloodAvailable) reasons.push('Blood bank'); else { warnings.push('No blood'); score -= 10; } }
    if (h.stale) { warnings.push(h.ageMin == null ? 'Status never updated' : 'Status is ' + Math.round(h.ageMin / 60) + ' h old'); score -= 20; }
    if (distKm > 40) { warnings.push('Very far'); score -= 30; }
    return {
      id: h.id, name: h.name, area: h.area, phone: h.phone, lat: h.lat, lng: h.lng,
      distance: h.distance, etaMin, score: Math.round(score), ready: h.ready,
      icuAvailable: h.icuAvailable, oxygenLevel: h.oxygenLevel, ventilatorsAvailable: h.ventilatorsAvailable,
      emergencyDoctor: h.emergencyDoctor, specialties: specs, reasons, warnings,
    };
  });
  out.sort((a, b) => b.score - a.score);
  return { type: NEEDS[type] ? type : 'general', label: need.label, best: out[0] || null, ranked: out.slice(0, 10) };
}

// ======================================================================= green corridor
function corridorFor(trip) {
  const mps = trip.speed > 3 ? trip.speed : 8;
  return (trip.junctions || []).map((j) => {
    const d = j.chain - trip.chain;
    let state = 'NORMAL';
    if (d < -25) state = 'RESTORED';
    else if (d <= 500) state = 'GREEN';
    else if (d <= 1500) state = 'PREPARE';
    return { id: j.id, name: j.name, lat: r6(j.lat), lng: r6(j.lng), distance: Math.round(d), state, etaSec: d > 0 ? Math.round(d / mps) : 0 };
  });
}

// ======================================================================= push (ntfy)
// ntfy is a free push service. Install the "ntfy" app (Play Store), subscribe to the topic the
// AmbuRoute app shows, and alerts ring even when AmbuRoute is fully closed.
const NTFY_URL = (process.env.NTFY_URL || 'https://ntfy.sh').replace(/\/+$/, '');
const NTFY_ON = !['0', 'false', 'no'].includes(String(process.env.NTFY_ENABLED || 'true').toLowerCase());
const SALT = process.env.PUSH_SALT || process.env.ADMIN_CODE || 'amburoute';
function topicFor(role, id) {
  return 'amburoute-' + role.slice(0, 1) + '-' + crypto.createHash('sha256').update(SALT + '|' + role + '|' + id).digest('hex').slice(0, 16);
}
const pushLog = [];
async function push(topic, { title, message, priority = 4, tags = 'ambulance', click }) {
  pushLog.push({ t: now(), topic, title });
  if (pushLog.length > 100) pushLog.shift();
  if (!NTFY_ON || process.env.NODE_ENV === 'test') return;
  try {
    const headers = { Title: String(title).replace(/[^\x20-\x7e]/g, ''), Priority: String(priority), Tags: tags };
    if (click) headers.Click = click;
    await fetch(NTFY_URL + '/' + topic, { method: 'POST', body: String(message), headers });
  } catch (e) { console.warn('push failed:', e.message); }
}

// ======================================================================= install
function install(ctx) {
  const { app, io, engine, hospitals, store, guard, limit, wrap, adminGuard, parsePoint, routing, roads, auth, hospitalReplies, bedBookings, publicBase } = ctx;
  const pub = (f) => path.join(__dirname, 'public', f);

  // ---------------- auth (OTP) ----------------
  app.post('/api/auth/otp/request', limit(6), wrap(async (req, res) => res.json(await auth.requestOtp(req.body || {}))));
  app.post('/api/auth/otp/verify', limit(12), wrap(async (req, res) => res.json(auth.verifyOtp(req.body || {}))));
  app.get('/api/auth/me', (req, res) => {
    const s = auth.checkToken(req.get('x-auth-token'));
    if (!s) return res.status(401).json({ error: 'Not logged in.', code: 'LOGIN_EXPIRED' });
    res.json({ ok: true, user: { phone: s.user.phone, role: s.role, name: s.user.name, ambulanceId: s.user.ambulanceId } });
  });
  app.post('/api/auth/logout', (req, res) => { auth.logout(req.get('x-auth-token')); res.json({ ok: true }); });
  app.get('/api/auth/mode', (req, res) => res.json({ ok: true, sms: auth.smsMode(), requireOtp: ctx.REQUIRE_OTP }));
  app.get('/api/admin/users', adminGuard, (req, res) => res.json({ ok: true, users: auth.listUsers() }));
  app.post('/api/admin/users', adminGuard, wrap(async (req, res) => res.json({ ok: true, user: auth.saveUser(req.body || {}) })));
  app.delete('/api/admin/users/:id', adminGuard, (req, res) => res.json({ ok: auth.removeUser(req.params.id) }));

  // ---------------- best hospital ----------------
  // (registered in server.js before /api/hospitals/:id so the path is not taken as a hospital id)
  const bestHandler = (req, res) => {
    const near = parsePoint({ lat: req.query.lat, lng: req.query.lng });
    if (!near) return res.status(400).json({ error: 'Your location is needed.', code: 'BAD_LOCATION' });
    const type = String(req.query.type || 'general');
    res.json({ ok: true, ...rankHospitals(hospitals, near, type, req.query.critical === '1' || req.query.critical === 'true') });
  };

  // ---------------- patient: emergency type + vitals ----------------
  app.post('/api/trips/:id/patient', guard('driver'), wrap(async (req, res) => {
    const trip = engine.getTrip(req.params.id);
    const b = req.body || {};
    trip.emergencyType = NEEDS[b.emergencyType] ? b.emergencyType : (trip.emergencyType || 'general');
    trip.patient = { age: num(b.age, 0, 120), gender: ['M', 'F', 'O'].includes(b.gender) ? b.gender : null, bloodGroup: txt(b.bloodGroup, 4), complaint: txt(b.complaint, 120) };
    io.to('trip:' + trip.id).emit('patient', { t: now() });
    res.json({ ok: true, emergencyType: trip.emergencyType, patient: trip.patient });
  }));

  function recordVitals(trip, body, source) {
    const v = cleanVitals(body, source);
    const list = vitalsByTrip.get(trip.id) || [];
    const prev = list.length ? list[list.length - 1] : null;
    list.push(v);
    if (list.length > 120) list.splice(0, list.length - 120);
    vitalsByTrip.set(trip.id, list);
    trip.triage = v.triage.level;
    io.to('trip:' + trip.id).emit('vitals', { t: now() });
    const h = destHospital(trip);
    if (h) {
      io.to('hospital:' + h.id).emit('vitals', { tripId: trip.id, t: now() });
      if (v.triage.level === 'red' && (!prev || prev.triage.level !== 'red')) {
        push(topicFor('hospital', h.id), { title: 'CRITICAL patient - ' + trip.ambulanceId, message: v.triage.flags.join(', ') + '. Prepare the trauma team.', priority: 5, tags: 'rotating_light', click: publicBaseStatic + '/er/' + h.id });
      }
    }
    return v;
  }
  app.post('/api/trips/:id/vitals', guard('driver'), limit(120), wrap(async (req, res) => {
    const trip = engine.getTrip(req.params.id);
    res.json({ ok: true, vitals: recordVitals(trip, req.body || {}, 'paramedic') });
  }));
  app.get('/api/trips/:id/vitals', guard('any'), limit(240), wrap(async (req, res) => {
    const trip = engine.getTrip(req.params.id);
    res.json({ ok: true, latest: latestVitals(trip.id), history: (vitalsByTrip.get(trip.id) || []).slice(-40), emergencyType: trip.emergencyType || 'general', patient: trip.patient || null });
  }));

  // ---------------- offline mode: GPS points saved without network ----------------
  app.post('/api/trips/:id/locations', guard('driver'), limit(60), wrap(async (req, res) => {
    const pts = Array.isArray((req.body || {}).points) ? req.body.points.slice(-300) : [];
    pts.sort((a, b) => (Number(a.t) || 0) - (Number(b.t) || 0));
    let out = null;
    const trip = engine.getTrip(req.params.id);
    trip.offlinePoints = (trip.offlinePoints || 0) + pts.length;
    for (const p of pts) { try { out = engine.updateLocation(req.params.id, p); } catch (_) {} }
    res.json({ ...(out || engine.tripView(trip)), accepted: pts.length, hospitalReply: hospitalReplies.get(req.params.id) || null });
  }));

  // ---------------- green corridor ----------------
  app.get('/api/trips/:id/corridor', guard('any'), limit(240), wrap(async (req, res) => {
    const trip = engine.getTrip(req.params.id);
    res.json({ ok: true, signals: corridorFor(trip) });
  }));

  // ---------------- smart roads ----------------
  app.post('/api/road/bumps', guard('driver'), limit(60), wrap(async (req, res) => res.json(roads.addBumps((req.body || {}).points, 'app'))));
  app.post('/api/road/narrow', guard('any'), limit(30), wrap(async (req, res) => res.json({ ok: true, cell: roads.reportNarrow(req.body || {}) })));
  app.get('/api/road/hazards', guard('any'), limit(60), (req, res) => {
    const near = parsePoint({ lat: req.query.lat, lng: req.query.lng });
    res.json({ ok: true, hazards: roads.hazardsNear(near, 8000), crossings: roads.listCrossings(near, 30000) });
  });
  app.get('/api/railway', guard('any'), limit(60), (req, res) => {
    const near = parsePoint({ lat: req.query.lat, lng: req.query.lng });
    res.json({ ok: true, crossings: roads.listCrossings(near, near ? 50000 : Infinity) });
  });
  app.post('/api/railway', guard('any'), limit(20), wrap(async (req, res) => res.json({ ok: true, crossing: roads.saveCrossing(req.body || {}) })));
  app.post('/api/railway/:id/status', guard('any'), limit(60), wrap(async (req, res) => {
    const b = req.body || {};
    const c = roads.setCrossingStatus(req.params.id, String(b.status || ''), b.by || 'app');
    io.emit('railway', { id: c.id, status: c.status });
    res.json({ ok: true, crossing: c });
  }));
  app.delete('/api/admin/railway/:id', adminGuard, (req, res) => res.json({ ok: store.remove('crossings', req.params.id) }));

  // ---------------- push topics ----------------
  app.get('/api/push/topic', guard('any'), (req, res) => {
    const role = ['police', 'hospital', 'driver'].includes(req.query.role) ? req.query.role : '';
    const id = txt(String(req.query.id || ''), 40);
    if (!role || !id) return res.status(400).json({ error: 'role and id are needed', code: 'BAD_TOPIC' });
    const topic = topicFor(role, id);
    res.json({ ok: true, enabled: NTFY_ON, topic, server: NTFY_URL, subscribeUrl: NTFY_URL + '/' + topic, appLink: 'ntfy://' + NTFY_URL.replace(/^https?:\/\//, '') + '/' + topic });
  });

  // ---------------- public SOS ----------------
  const sosList = new Map();
  const sosView = (s, full) => {
    const out = { id: s.id, type: s.type, note: s.note, lat: s.lat, lng: s.lng, status: s.status, createdAt: s.createdAt, acceptedAt: s.acceptedAt || null, ambulanceId: s.ambulanceId || null };
    if (full && s.phone) out.phone = s.phone;
    return out;
  };
  app.post('/api/sos', limit(5), wrap(async (req, res) => {
    const b = req.body || {};
    const p = parsePoint(b);
    if (!p) throw engine.httpError(400, 'Location is needed. Please allow location in the browser.', 'BAD_LOCATION');
    const id = crypto.randomBytes(6).toString('base64url');
    const s = { id, ...p, type: NEEDS[b.type] ? b.type : 'general', note: txt(b.note, 160), phone: auth.cleanPhone(b.phone), status: 'open', createdAt: now() };
    sosList.set(id, s);
    io.emit('sos', { id });
    push(topicFor('driver', 'all'), { title: 'SOS emergency nearby', message: (NEEDS[s.type].label) + (s.note ? ': ' + s.note : ''), priority: 5, tags: 'sos' });
    res.json({ ok: true, id, statusUrl: publicBase(req) + '/sos?id=' + id });
  }));
  app.get('/api/sos/open', guard('driver'), limit(120), (req, res) => {
    const near = parsePoint({ lat: req.query.lat, lng: req.query.lng });
    const list = [...sosList.values()].filter((s) => s.status === 'open' && now() - s.createdAt < 60 * 60 * 1000)
      .map((s) => ({ ...sosView(s, true), distance: near ? Math.round(haversine(near, s)) : null }))
      .filter((s) => s.distance == null || s.distance < 40000)
      .sort((a, b) => (a.distance ?? 0) - (b.distance ?? 0));
    res.json({ ok: true, sos: list });
  });
  app.post('/api/sos/:id/accept', guard('driver'), wrap(async (req, res) => {
    const s = sosList.get(req.params.id);
    if (!s) throw engine.httpError(404, 'This SOS is no longer open.', 'SOS_NOT_FOUND');
    if (s.status !== 'open') throw engine.httpError(409, 'Another ambulance already accepted this SOS.', 'SOS_TAKEN');
    s.status = 'assigned';
    s.ambulanceId = txt((req.body || {}).ambulanceId, 20).toUpperCase() || 'AMB';
    s.acceptedAt = now();
    io.emit('sos', { id: s.id });
    res.json({ ok: true, sos: sosView(s, true) });
  }));
  app.get('/api/sos/:id', limit(120), (req, res) => {
    const s = sosList.get(req.params.id);
    if (!s) return res.status(404).json({ error: 'SOS not found or expired.', code: 'SOS_NOT_FOUND' });
    let amb = null;
    if (s.ambulanceId) {
      const t = engine.activeTrips().find((x) => x.ambulanceId === s.ambulanceId);
      if (t) {
        const v = engine.tripView(t);
        const toPatient = haversine(t.to, s) < 300;
        amb = { lat: r6(t.pos.lat), lng: r6(t.pos.lng), speedKmh: Math.round((t.speed || 0) * 3.6), etaSec: toPatient ? v.etaSec : null, remaining: toPatient ? v.remaining : null, toPatient };
      }
    }
    res.set('Cache-Control', 'no-store').json({ ok: true, sos: sosView(s, false), ambulance: amb });
  });
  app.get('/sos', (req, res) => res.sendFile(pub('sos.html')));

  // ---------------- admin live map + report ----------------
  function thin(points, max = 120) {
    const step = Math.max(1, Math.ceil(points.length / max));
    return points.filter((_, i) => i % step === 0 || i === points.length - 1).map((p) => [r6(p.lat), r6(p.lng)]);
  }
  function destHospital(trip) {
    const booking = bedBookings.get(trip.id);
    const list = store.list('hospitals');
    if (booking) {
      const byId = list.find((h) => h.id === booking.hospitalId || h.name.toLowerCase() === String(booking.hospitalName || '').toLowerCase());
      if (byId) return byId;
    }
    return list.find((h) => trip.to && haversine(trip.to, h) < 400) || null;
  }
  function liveTrip(trip) {
    const v = engine.tripView(trip);
    const lv = latestVitals(trip.id);
    const h = destHospital(trip);
    return {
      tripId: trip.id, ambulanceId: trip.ambulanceId, driverName: trip.driverName, demo: !!trip.demo,
      lat: r6(trip.pos.lat), lng: r6(trip.pos.lng), speedKmh: Math.round((trip.speed || 0) * 3.6),
      destination: trip.destName || 'Hospital', dest: { lat: r6(trip.to.lat), lng: r6(trip.to.lng) },
      hospitalId: h ? h.id : null,
      remaining: v.remaining, etaSec: v.etaSec, status: v.status, priority: trip.priority,
      emergencyType: trip.emergencyType || 'general', routeMode: trip.routeMode || 'fast',
      triage: lv ? lv.triage : null, vitals: lv,
      startedAt: trip.startedAt, gpsAgeSec: Math.round((now() - trip.lastUpdate) / 1000),
      hospitalReply: hospitalReplies.get(trip.id) || null,
      route: thin(trip.route.points), corridor: corridorFor(trip),
    };
  }
  app.get('/api/admin/live', adminGuard, (req, res) => {
    const t = now();
    res.json({
      ok: true, serverTime: t,
      trips: engine.activeTrips().map(liveTrip),
      posts: engine.allPosts().map((p) => ({ id: p.id, name: p.name, lat: p.lat, lng: p.lng, radius: p.radius, online: p.onDuty && t - p.lastSeen < engine.CFG.POST_STALE_MS })),
      hospitals: hospitals.live(null).map((h) => ({ id: h.id, name: h.name, lat: h.lat, lng: h.lng, ready: h.ready, icuAvailable: h.icuAvailable, oxygenLevel: h.oxygenLevel, specialties: h.specialties || [] })),
      crossings: roads.listCrossings(null),
      hazards: roads.hazardsNear(null),
      sos: [...sosList.values()].filter((s) => s.status !== 'closed' && t - s.createdAt < 3 * 3600 * 1000).map((s) => sosView(s, false)),
      pushes: pushLog.slice(-15).reverse(),
    });
  });
  app.get('/api/admin/report', adminGuard, (req, res) => {
    const trips = store.list('trips');
    const done = trips.filter((x) => x.endedAt && x.startedAt);
    const dur = done.map((x) => (x.endedAt - x.startedAt) / 1000).filter((d) => d > 30);
    const avg = (a) => (a.length ? Math.round(a.reduce((s, x) => s + x, 0) / a.length) : 0);
    const days = {};
    for (let i = 13; i >= 0; i--) { const d = new Date(now() - i * 86400000).toISOString().slice(0, 10); days[d] = { day: d, trips: 0, avgMin: 0, _sum: 0 }; }
    for (const x of done) {
      const d = new Date(x.startedAt).toISOString().slice(0, 10);
      if (!days[d]) continue;
      days[d].trips++; days[d]._sum += (x.endedAt - x.startedAt) / 60000;
    }
    const perDay = Object.values(days).map((d) => ({ day: d.day, trips: d.trips, avgMin: d.trips ? Math.round(d._sum / d.trips) : 0 }));
    const perAmb = {};
    for (const x of done) {
      const a = perAmb[x.ambulanceId] || (perAmb[x.ambulanceId] = { ambulanceId: x.ambulanceId, trips: 0, km: 0, _min: 0 });
      a.trips++; a.km += (x.travelled || 0) / 1000; a._min += (x.endedAt - x.startedAt) / 60000;
    }
    const sos = [...sosList.values()].filter((s) => s.acceptedAt);
    res.json({
      ok: true,
      totalTrips: trips.length,
      completed: trips.filter((x) => x.status === 'completed').length,
      avgTripMin: Math.round(avg(dur) / 60),
      goldenHourPct: dur.length ? Math.round((dur.filter((d) => d <= 3600).length / dur.length) * 100) : 0,
      critical: trips.filter((x) => x.priority === 'critical').length,
      avgSosResponseSec: avg(sos.map((s) => (s.acceptedAt - s.createdAt) / 1000)),
      byType: trips.reduce((m, x) => { const k = x.emergencyType || 'general'; m[k] = (m[k] || 0) + 1; return m; }, {}),
      perDay,
      perAmbulance: Object.values(perAmb).map((a) => ({ ambulanceId: a.ambulanceId, trips: a.trips, km: Math.round(a.km * 10) / 10, avgMin: Math.round(a._min / a.trips) })).sort((a, b) => b.trips - a.trips),
    });
  });
  app.get('/admin/live', (req, res) => res.sendFile(pub('live.html')));

  // ---------------- hospital ER web dashboard (big screen in the ER) ----------------
  app.get('/er/:hospitalId', (req, res) => res.sendFile(pub('er.html')));

  // ---------------- background push watchers ----------------
  let publicBaseStatic = process.env.PUBLIC_URL ? String(process.env.PUBLIC_URL).replace(/\/+$/, '') : '';
  app.use((req, res, next) => { if (!publicBaseStatic && req.get('host')) publicBaseStatic = publicBase(req); next(); });

  // police: wrap the engine notifier, push once per (post, trip) when the ambulance is approaching
  const pushedPost = new Map(); // postId|tripId -> level pushed
  const oldNotifier = ctx.notify;
  engine.setNotifier((msg) => {
    try { oldNotifier(msg); } catch (_) {}
    if (!msg || typeof msg.room !== 'string' || !msg.room.startsWith('post:')) return;
    const postId = msg.room.slice(5);
    const post = engine.allPosts().find((p) => p.id === postId);
    if (!post) return;
    const keepSeen = post.lastSeen;
    let data;
    try { data = engine.alertsForPost(postId); } catch (_) { return; } finally { post.lastSeen = keepSeen; }
    for (const a of data.alerts || []) {
      const level = a.status === 'imminent' ? 2 : a.status === 'approaching' || a.status === 'test' ? 1 : 0;
      if (!level) continue;
      const key = postId + '|' + a.tripId;
      if ((pushedPost.get(key) || 0) >= level) continue;
      pushedPost.set(key, level);
      const eta = a.etaSec != null ? Math.max(1, Math.round(a.etaSec / 60)) + ' min' : 'soon';
      push(topicFor('police', postId), {
        title: (a.priority === 'critical' ? 'CRITICAL ' : '') + 'Ambulance ' + a.ambulanceId + (level === 2 ? ' is very close' : ' approaching'),
        message: `${a.distAhead} m away, ETA ${eta}. Please clear the junction.`,
        priority: level === 2 || a.priority === 'critical' ? 5 : 4, tags: 'rotating_light,ambulance',
      });
    }
    if (pushedPost.size > 5000) pushedPost.clear();
  });

  // hospital: push when a NEW ambulance starts coming
  const pushedHosp = new Set();
  setInterval(() => {
    for (const trip of engine.activeTrips()) {
      const h = destHospital(trip);
      if (!h) continue;
      const key = h.id + '|' + trip.id;
      if (pushedHosp.has(key)) continue;
      pushedHosp.add(key);
      const v = engine.tripView(trip);
      push(topicFor('hospital', h.id), {
        title: 'Incoming ambulance ' + trip.ambulanceId,
        message: `ETA ${Math.max(1, Math.round(v.etaSec / 60))} min, ${(v.remaining / 1000).toFixed(1)} km. Type: ${(NEEDS[trip.emergencyType] || NEEDS.general).label}${trip.priority === 'critical' ? ', CRITICAL' : ''}. Open the Hospital app to reply.`,
        priority: trip.priority === 'critical' ? 5 : 4, tags: 'ambulance,hospital',
        click: publicBaseStatic ? publicBaseStatic + '/er/' + h.id : undefined,
      });
    }
    if (pushedHosp.size > 5000) pushedHosp.clear();
  }, 8000).unref();

  // ---------------- DEMO simulator ----------------
  const demos = new Map(); // tripId -> timer
  async function seedDemo(center) {
    const off = (dLat, dLng) => ({ lat: r6(center.lat + dLat), lng: r6(center.lng + dLng) });
    const H = [
      { name: 'DEMO City Heart Institute', p: off(0.030, 0.020), st: { icuTotal: 10, icuAvailable: 3, ventilatorsAvailable: 2, oxygenLevel: 'ok', oxygenAvailable: true, emergencyDoctor: true, bloodAvailable: true, specialties: ['cardiac', 'general'], bloodGroups: ['O+', 'B+'] } },
      { name: 'DEMO Trauma & Burn Centre', p: off(0.025, -0.028), st: { icuTotal: 12, icuAvailable: 2, ventilatorsAvailable: 3, traumaBeds: 4, oxygenLevel: 'ok', oxygenAvailable: true, emergencyDoctor: true, bloodAvailable: true, specialties: ['trauma', 'burn', 'general'], bloodGroups: ['O+', 'O-', 'A+'] } },
      { name: 'DEMO Neuro & Stroke Hospital', p: off(-0.022, 0.026), st: { icuTotal: 8, icuAvailable: 1, ventilatorsAvailable: 1, oxygenLevel: 'low', oxygenAvailable: true, emergencyDoctor: true, bloodAvailable: false, specialties: ['stroke', 'neuro'] } },
      { name: 'DEMO Sadar Hospital (ICU full)', p: off(0.008, 0.006), st: { icuTotal: 6, icuAvailable: 0, ventilatorsAvailable: 0, oxygenLevel: 'none', oxygenAvailable: false, emergencyDoctor: false, specialties: ['general'] } },
    ];
    const made = [];
    for (const x of H) {
      const h = hospitals.register({ name: x.name, area: 'Demo', phone: '102', lat: x.p.lat, lng: x.p.lng });
      hospitals.updateStatus(h.id, x.st);
      made.push(h);
    }
    roads.saveCrossing({ id: 'RX-DEMO-1', name: 'DEMO Railway Gate 1', lat: center.lat + 0.012, lng: center.lng + 0.009 });
    roads.setCrossingStatus('RX-DEMO-1', 'closed', 'demo');
    roads.saveCrossing({ id: 'RX-DEMO-2', name: 'DEMO Railway Gate 2', lat: center.lat - 0.010, lng: center.lng - 0.012 });
    roads.setCrossingStatus('RX-DEMO-2', 'open', 'demo');
    return made;
  }
  async function startDemoTrip(center, type) {
    const from = { lat: r6(center.lat - 0.02), lng: r6(center.lng - 0.01) };
    const rank = rankHospitals(hospitals, from, type, true);
    const best = rank.best;
    const to = best ? { lat: best.lat, lng: best.lng } : { lat: center.lat + 0.03, lng: center.lng + 0.02 };
    const rd = await routing.getRoute(from, to, { mode: type === 'trauma' ? 'smooth' : 'fast' });
    // crowdsourced potholes on part of the route, so the "smooth route" logic has data to show
    roads.addBumps(rd.route.points.filter((_, i) => i % 9 === 3).slice(0, 25).map((p) => ({ lat: p.lat, lng: p.lng, g: 8 })), 'demo');
    const n = [...demos.keys()].length + 1;
    const trip = engine.startTrip({ driverName: 'Demo Driver', ambulanceId: 'DEMO-' + n, from, to, routeData: rd, destinationName: best ? best.name : 'Demo hospital' });
    trip.demo = true; trip.emergencyType = type; trip.routeMode = rd.mode; trip.priority = 'critical';
    trip.patient = { age: 54, gender: 'M', bloodGroup: 'B+', complaint: type === 'cardiac' ? 'Chest pain, sweating' : 'Road accident' };
    if (best) bedBookings.set(trip.id, { tripId: trip.id, ambulanceId: trip.ambulanceId, hospitalId: best.id, hospitalName: best.name, bedType: 'Emergency ICU Bed', patientBrief: trip.patient.complaint, status: 'CONFIRMED', bookedAt: now() });
    let dist = 0, tick = 0;
    const mps = 13; // ~47 km/h
    const timer = setInterval(() => {
      try {
        tick++;
        dist = Math.min(trip.route.total, dist + mps * 2);
        const pts = trip.route.points, cum = trip.route.cum;
        let i = 0;
        while (i < cum.length - 2 && cum[i + 1] < dist) i++;
        const seg = cum[i + 1] - cum[i] || 1;
        const f = Math.max(0, Math.min(1, (dist - cum[i]) / seg));
        const p = { lat: pts[i].lat + (pts[i + 1].lat - pts[i].lat) * f, lng: pts[i].lng + (pts[i + 1].lng - pts[i].lng) * f };
        engine.updateLocation(trip.id, { ...p, speed: mps, acc: 5 });
        if (tick % 3 === 1) {
          const worse = Math.min(1, tick / 40);
          recordVitals(trip, {
            hr: Math.round(96 + worse * 40 + Math.random() * 6), spo2: Math.round(96 - worse * 9 - Math.random() * 2),
            bpSys: Math.round(128 - worse * 40), bpDia: Math.round(82 - worse * 20), rr: Math.round(18 + worse * 10),
            gcs: 14, ecg: type === 'cardiac' && tick > 12 ? 'stemi' : 'normal', note: 'Auto demo vitals (IoT)',
          }, 'iot');
        }
        if (!trip.active || dist >= trip.route.total) { clearInterval(timer); demos.delete(trip.id); }
      } catch (_) { clearInterval(timer); demos.delete(trip.id); }
    }, 2000);
    timer.unref();
    demos.set(trip.id, timer);
    return { trip, best };
  }
  app.post('/api/demo/start', adminGuard, wrap(async (req, res) => {
    const b = req.body || {};
    const center = parsePoint(b) || { lat: 25.5941, lng: 85.1376 }; // Patna by default
    const type = NEEDS[b.type] ? b.type : 'cardiac';
    if (b.seed !== false) await seedDemo(center);
    const { trip, best } = await startDemoTrip(center, type);
    const share = publicBase(req);
    res.json({ ok: true, tripId: trip.id, ambulanceId: trip.ambulanceId, hospital: best ? best.name : null, erUrl: best ? share + '/er/' + best.id : null });
  }));
  app.post('/api/demo/stop', adminGuard, (req, res) => {
    for (const [id, t] of demos) { clearInterval(t); try { engine.stopTrip(id); } catch (_) {} }
    const n = demos.size; demos.clear();
    res.json({ ok: true, stopped: n });
  });

  return { bestHandler, latestVitals, recordVitals, corridorFor, rankHospitals: (near, type, c) => rankHospitals(hospitals, near, type, c), topicFor, triage };
}

module.exports = { install, triage, rankHospitals, corridorFor, cleanVitals, topicFor, NEEDS };

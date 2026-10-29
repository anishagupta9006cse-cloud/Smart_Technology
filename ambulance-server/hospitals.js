'use strict';
// Live hospital status: ICU beds, oxygen, ventilators, doctors on duty, and specialty resources.
// Hospital staff update it from the Hospital app; ambulance drivers and AI engine read it.
const { haversine } = require('./geo');

let store = null;
function init(s) { store = s; }

const num = (v, min, max, def = 0) => {
  const n = Math.round(Number(v));
  if (!Number.isFinite(n)) return def;
  return Math.max(min, Math.min(max, n));
};
const txt = (v, n) => (typeof v === 'string' ? v.replace(/[\u0000-\u001f<>]/g, ' ').trim().slice(0, n) : '');
const bool = (v) => v === true || v === 'true' || v === 1 || v === '1';
const rid = () => 'H' + Math.random().toString(36).slice(2, 8).toUpperCase() + Date.now().toString(36).slice(-3).toUpperCase();

function cleanStatus(b, old) {
  b = b || {};
  const icuTotal = num(b.icuTotal, 0, 500, old ? old.icuTotal : 0);
  const oxygenLevel = ['ok', 'low', 'none'].includes(b.oxygenLevel) ? b.oxygenLevel : (old ? old.oxygenLevel : 'ok');
  return {
    icuTotal,
    icuAvailable: Math.min(icuTotal, num(b.icuAvailable, 0, 500, old ? old.icuAvailable : 0)),
    ventilatorsAvailable: num(b.ventilatorsAvailable, 0, 500, old ? old.ventilatorsAvailable : 0),
    traumaBeds: num(b.traumaBeds, 0, 500, old ? old.traumaBeds : 0),
    generalBeds: num(b.generalBeds, 0, 1000, old ? old.generalBeds : 0),
    oxygenAvailable: oxygenLevel !== 'none' && ('oxygenAvailable' in b ? bool(b.oxygenAvailable) : (old ? old.oxygenAvailable : true)),
    oxygenLevel,
    oxygenCylinders: num(b.oxygenCylinders, 0, 5000, old ? old.oxygenCylinders : 0),
    emergencyDoctor: 'emergencyDoctor' in b ? bool(b.emergencyDoctor) : (old ? old.emergencyDoctor : true),
    bloodAvailable: 'bloodAvailable' in b ? bool(b.bloodAvailable) : (old ? old.bloodAvailable : false),
    cathLab: 'cathLab' in b ? bool(b.cathLab) : (old ? old.cathLab : true),
    ctScan: 'ctScan' in b ? bool(b.ctScan) : (old ? old.ctScan : true),
    burnUnit: 'burnUnit' in b ? bool(b.burnUnit) : (old ? old.burnUnit : false),
    bloodBankStock: 'bloodBankStock' in b ? txt(b.bloodBankStock, 60) : (old ? old.bloodBankStock : 'A+, B+, O+, AB+ available'),
    notes: 'notes' in b ? txt(b.notes, 160) : (old ? old.notes : ''),
  };
}

function register(b) {
  b = b || {};
  const name = txt(b.name, 80);
  if (name.length < 2) { const e = new Error('Please enter the hospital name.'); e.status = 400; e.code = 'BAD_NAME'; throw e; }
  const lat = Number(b.lat), lng = Number(b.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
    const e = new Error('Hospital location is missing. Use GPS in the app.'); e.status = 400; e.code = 'BAD_POINT'; throw e;
  }
  let h = b.id ? store.get('hospitals', String(b.id)) : null;
  if (!h) {
    h = store.list('hospitals').find((x) => x.name.toLowerCase() === name.toLowerCase() && haversine(x, { lat, lng }) < 500) || null;
  }
  const now = Date.now();
  const rec = {
    id: h ? h.id : rid(),
    name, area: txt(b.area, 100), phone: txt(b.phone, 30), lat, lng,
    registeredAt: h ? h.registeredAt : now,
    updatedAt: h ? h.updatedAt : 0,
    lastSeen: now,
    status: h ? h.status : cleanStatus({ icuTotal: 6, icuAvailable: 4, oxygenLevel: 'ok', oxygenAvailable: true, emergencyDoctor: true, bloodAvailable: true, cathLab: true, ctScan: true }, null),
  };
  return store.put('hospitals', rec);
}

function updateStatus(id, b) {
  const h = store.get('hospitals', String(id));
  if (!h) { const e = new Error('Hospital not found. Please register again.'); e.status = 404; e.code = 'HOSPITAL_NOT_FOUND'; throw e; }
  const now = Date.now();
  const rec = { ...h, status: cleanStatus(b, h.status), updatedAt: now, lastSeen: now };
  return store.put('hospitals', rec);
}

function touch(id) {
  const h = store.get('hospitals', String(id));
  if (h) h.lastSeen = Date.now();
  return h;
}

const FRESH_MS = 6 * 3600 * 1000;

function view(h, near) {
  const s = h.status;
  const age = h.updatedAt ? Date.now() - h.updatedAt : null;
  const stale = age === null || age > FRESH_MS;
  const problems = [];
  if (s.icuAvailable <= 0) problems.push('No ICU bed');
  if (!s.oxygenAvailable) problems.push('No oxygen');
  else if (s.oxygenLevel === 'low') problems.push('Oxygen LOW');
  if (!s.emergencyDoctor) problems.push('No emergency doctor');
  let ready = 'ready';
  if (stale) ready = 'unknown';
  else if (s.icuAvailable <= 0 || !s.oxygenAvailable || !s.emergencyDoctor) ready = 'not_ready';
  else if (problems.length) ready = 'limited';
  return {
    id: h.id, name: h.name, area: h.area, phone: h.phone, lat: h.lat, lng: h.lng,
    ...s,
    updatedAt: h.updatedAt, ageMin: age === null ? null : Math.round(age / 60000), stale,
    ready, problems,
    distance: near ? Math.round(haversine(near, h)) : null,
  };
}

function live(near) {
  const out = store.list('hospitals').map((h) => view(h, near));
  const rank = { ready: 0, limited: 1, unknown: 2, not_ready: 3 };
  out.sort((a, b) => (rank[a.ready] - rank[b.ready]) || ((a.distance ?? 0) - (b.distance ?? 0)) || a.name.localeCompare(b.name));
  return out;
}

// AI Recommendation: Computes the Best Hospital based on ETA, ICU Bed, Oxygen, Doctor, and Specialty Match
function recommendBestHospital({ near, emergencyType = 'general', routeMode = 'smooth' }) {
  const allHospitals = store.list('hospitals').map((h) => view(h, near));
  if (!allHospitals.length) return { bestHospital: null, ranked: [] };

  const ranked = allHospitals.map(h => {
    let score = 100;
    const reasons = [];

    // Distance & ETA factor (assume 40 km/h avg emergency speed)
    const distKm = (h.distance || 1000) / 1000;
    const etaMin = Math.round(distKm * 1.5);
    score -= Math.min(40, distKm * 3); // 3 pts penalty per km

    // ICU Bed check
    if (h.icuAvailable > 0) {
      reasons.push(`${h.icuAvailable} ICU beds free`);
    } else {
      score -= 35;
      reasons.push('ICU beds FULL (-35 pts)');
    }

    // Oxygen check
    if (!h.oxygenAvailable) {
      score -= 30;
      reasons.push('No oxygen available (-30 pts)');
    } else if (h.oxygenLevel === 'low') {
      score -= 12;
      reasons.push('Oxygen LOW (-12 pts)');
    } else {
      reasons.push('Oxygen Supply OK');
    }

    // Emergency Doctor
    if (!h.emergencyDoctor) {
      score -= 25;
      reasons.push('No ER Doctor on duty (-25 pts)');
    } else {
      reasons.push('ER Doctor Active');
    }

    // Specialty matching
    const eType = (emergencyType || 'general').toLowerCase();
    if (eType === 'cardiac' || eType === 'cardio') {
      if (h.cathLab) { score += 15; reasons.push('Cath Lab / STEMI Ready (+15 pts)'); }
      else { score -= 20; reasons.push('No Cath Lab for Cardiac (-20 pts)'); }
    } else if (eType === 'trauma') {
      if (h.traumaBeds > 0 && h.bloodAvailable) { score += 15; reasons.push('Trauma OT & Blood Ready (+15 pts)'); }
      else { score -= 15; reasons.push('Limited Trauma Capacity (-15 pts)'); }
    } else if (eType === 'stroke') {
      if (h.ctScan) { score += 15; reasons.push('CT / Neuro Stroke Unit Ready (+15 pts)'); }
      else { score -= 20; reasons.push('No CT Scanner for Stroke (-20 pts)'); }
    } else if (eType === 'burn') {
      if (h.burnUnit) { score += 15; reasons.push('Specialized Burn ICU (+15 pts)'); }
      else { score -= 25; reasons.push('No Dedicated Burn Unit (-25 pts)'); }
    }

    // Road mode bonus
    if (routeMode === 'smooth') {
      score += 5;
      reasons.push('Smooth Trauma Corridor accessible');
    }

    const finalScore = Math.max(10, Math.min(100, Math.round(score)));
    return {
      ...h,
      aiScore: finalScore,
      etaMinutes: etaMin,
      recommendationReason: reasons.join(' • '),
      matchPercentage: `${finalScore}% Match`
    };
  });

  ranked.sort((a, b) => b.aiScore - a.aiScore);

  return {
    bestHospital: ranked[0] || null,
    ranked,
    evaluatedEmergency: emergencyType,
    generatedAt: Date.now()
  };
}

function get(id) { return store.get('hospitals', String(id)); }
function remove(id) { return store.remove('hospitals', String(id)); }

module.exports = { init, register, updateStatus, touch, live, view, get, remove, cleanStatus, recommendBestHospital };

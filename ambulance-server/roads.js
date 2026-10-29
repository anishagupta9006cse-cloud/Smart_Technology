'use strict';
// Real-world Indian road conditions for ambulance routing.
//   1. Potholes / rough bumps  -> crowdsourced from the phone accelerometer of every ambulance (driver app).
//   2. Railway crossings      -> gate status OPEN / CLOSED (police app, IoT sensor at the gate, or admin).
//   3. Narrow lanes            -> roads too narrow for a big ambulance (reported by drivers / admin).
// The route engine (routing.js) asks scoreRoute() for every possible route and picks the best one.
const { haversine } = require('./geo');

let store = null;
function init(s) { store = s; }

const CELL = 0.0005; // ~50 m grid
const cellKey = (lat, lng) => Math.round(lat / CELL) + ':' + Math.round(lng / CELL);
const cellCenter = (key) => { const [a, b] = key.split(':').map(Number); return { lat: a * CELL, lng: b * CELL }; };
const now = () => Date.now();
const BUMP_HALF_LIFE_MS = 30 * 24 * 3600 * 1000; // old pothole reports slowly fade (roads get repaired)
const GATE_CLOSED_TTL_MS = 12 * 60 * 1000;       // "closed" without an update for 12 min -> unknown
const txt = (v, n) => (typeof v === 'string' ? v.replace(/[\u0000-\u001f<>]/g, ' ').trim().slice(0, n) : '');
const httpErr = (status, msg, code) => { const e = new Error(msg); e.status = status; e.code = code; return e; };
const ok = (lat, lng) => Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180;

function decayed(cell) {
  const age = now() - (cell.updatedAt || 0);
  return (cell.bump || 0) * Math.pow(0.5, age / BUMP_HALF_LIFE_MS);
}

// ---------------- potholes / bumps ----------------
// points: [{ lat, lng, g }]  g = vertical shock in m/s² above normal gravity (phone accelerometer)
function addBumps(points, source = 'app') {
  if (!Array.isArray(points)) return { ok: true, saved: 0 };
  let saved = 0;
  for (const p of points.slice(0, 200)) {
    const lat = Number(p.lat), lng = Number(p.lng), g = Number(p.g);
    if (!ok(lat, lng) || !Number.isFinite(g) || g < 3) continue; // small shakes are ignored
    const sev = g >= 12 ? 3 : g >= 7 ? 2 : 1; // 1 = bump, 2 = pothole, 3 = very bad pothole
    const id = cellKey(lat, lng);
    const old = store.get('roadcells', id) || { id, bump: 0, reports: 0, narrow: 0 };
    const rec = { ...old, bump: Math.min(50, decayed(old) + sev), reports: (old.reports || 0) + 1, updatedAt: now(), source };
    store.put('roadcells', rec);
    saved++;
  }
  return { ok: true, saved };
}

function reportNarrow(b) {
  const lat = Number(b.lat), lng = Number(b.lng);
  if (!ok(lat, lng)) throw httpErr(400, 'Invalid location.', 'BAD_LOCATION');
  const width = Math.max(1, Math.min(20, Number(b.widthM) || 3));
  const id = cellKey(lat, lng);
  const old = store.get('roadcells', id) || { id, bump: 0, reports: 0 };
  const rec = { ...old, narrow: width < 4 ? 1 : 0, widthM: width, updatedAt: now(), note: txt(b.note, 80) };
  store.put('roadcells', rec);
  return rec;
}

// ---------------- railway crossings ----------------
function saveCrossing(b) {
  const lat = Number(b.lat), lng = Number(b.lng);
  if (!ok(lat, lng)) throw httpErr(400, 'Invalid crossing location.', 'BAD_LOCATION');
  const id = typeof b.id === 'string' && /^[A-Za-z0-9_-]{2,40}$/.test(b.id) ? b.id : 'RX' + Math.random().toString(36).slice(2, 7).toUpperCase();
  const old = store.get('crossings', id);
  const rec = {
    id, name: txt(b.name, 80) || 'Railway crossing', lat, lng,
    status: old ? old.status : 'unknown', updatedAt: old ? old.updatedAt : 0, by: old ? old.by : '',
    createdAt: old ? old.createdAt : now(),
  };
  return store.put('crossings', rec);
}

function setCrossingStatus(id, status, by) {
  const c = store.get('crossings', String(id));
  if (!c) throw httpErr(404, 'Railway crossing not found.', 'CROSSING_NOT_FOUND');
  const st = ['open', 'closed'].includes(status) ? status : 'unknown';
  return store.put('crossings', { ...c, status: st, updatedAt: now(), by: txt(by, 40) });
}

function crossingView(c) {
  let status = c.status;
  if (status === 'closed' && now() - c.updatedAt > GATE_CLOSED_TTL_MS) status = 'unknown';
  return { ...c, status, ageMin: c.updatedAt ? Math.round((now() - c.updatedAt) / 60000) : null };
}
function listCrossings(near, radiusM = 50000) {
  return store.list('crossings').map(crossingView)
    .map((c) => ({ ...c, distance: near ? Math.round(haversine(near, c)) : null }))
    .filter((c) => !near || c.distance <= radiusM)
    .sort((a, b) => (a.distance ?? 0) - (b.distance ?? 0));
}

// ---------------- route scoring ----------------
// Walks along the route every ~25 m and adds up what it finds.
function scoreRoute(route, mode) {
  const pts = route.points;
  const seen = new Set();
  let bumps = 0, narrow = 0, potholes = 0;
  const step = Math.max(1, Math.floor(pts.length / 600));
  for (let i = 0; i < pts.length; i += step) {
    const k = cellKey(pts[i].lat, pts[i].lng);
    if (seen.has(k)) continue;
    seen.add(k);
    const c = store.get('roadcells', k);
    if (!c) continue;
    const b = decayed(c);
    if (b >= 0.8) { bumps += b; if (b >= 2) potholes++; }
    if (c.narrow) narrow++;
  }
  const crossings = [];
  for (const c of store.list('crossings')) {
    // crossing within 40 m of any route point
    for (let i = 0; i < pts.length; i += step) {
      if (Math.abs(pts[i].lat - c.lat) > 0.001 || Math.abs(pts[i].lng - c.lng) > 0.001) continue;
      if (haversine(pts[i], c) < 40) { crossings.push(crossingView(c)); break; }
    }
  }
  const closed = crossings.filter((c) => c.status === 'closed').length;
  const unknown = crossings.filter((c) => c.status === 'unknown').length;
  const smoothScore = Math.max(0, Math.round(100 - bumps * 2 - potholes * 3));
  // cost in "seconds": how much worse is this route than its driving time says
  let penaltySec = closed * 300 + unknown * 45 + narrow * 90;
  if (mode === 'smooth') penaltySec += bumps * 25 + potholes * 40;
  else penaltySec += bumps * 4;
  return {
    bumps: Math.round(bumps), potholes, narrow, crossings: crossings.length, closedCrossings: closed,
    crossingList: crossings.map((c) => ({ id: c.id, name: c.name, status: c.status, lat: c.lat, lng: c.lng })),
    smoothScore, penaltySec: Math.round(penaltySec),
  };
}

function hazardsNear(near, radiusM = 5000) {
  const out = [];
  for (const c of store.list('roadcells')) {
    const p = cellCenter(c.id);
    if (near && haversine(near, p) > radiusM) continue;
    const b = decayed(c);
    if (b < 0.8 && !c.narrow) continue;
    out.push({ lat: p.lat, lng: p.lng, severity: b >= 6 ? 'high' : b >= 2 ? 'medium' : 'low', bump: Math.round(b * 10) / 10, narrow: !!c.narrow });
    if (out.length > 500) break;
  }
  return out;
}

module.exports = { init, addBumps, reportNarrow, saveCrossing, setCrossingStatus, listCrossings, scoreRoute, hazardsNear, cellKey };

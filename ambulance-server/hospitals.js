'use strict';
// Live hospital status: ICU beds, oxygen, ventilators, doctors on duty.
// Hospital staff update it from the Hospital app; ambulance drivers read it before choosing a hospital.
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

const SPECIALTIES = ['cardiac', 'trauma', 'stroke', 'burn', 'neuro', 'pediatric', 'maternity', 'general'];
const BLOOD = ['A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+', 'AB-'];

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
    notes: 'notes' in b ? txt(b.notes, 160) : (old ? old.notes : ''),
    // which emergencies this hospital can treat right now (doctor + equipment on duty)
    specialties: Array.isArray(b.specialties)
      ? [...new Set(b.specialties.map(String).filter((x) => SPECIALTIES.includes(x)))]
      : (old && Array.isArray(old.specialties) ? old.specialties : ['trauma']),
    // blood groups in stock, example ["O+","B+"]
    bloodGroups: Array.isArray(b.bloodGroups)
      ? [...new Set(b.bloodGroups.map(String).filter((x) => BLOOD.includes(x)))]
      : (old && Array.isArray(old.bloodGroups) ? old.bloodGroups : []),
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
    // same name + nearly same place = same hospital (so re-installing the app does not create a duplicate)
    h = store.list('hospitals').find((x) => x.name.toLowerCase() === name.toLowerCase() && haversine(x, { lat, lng }) < 500) || null;
  }
  const now = Date.now();
  const rec = {
    id: h ? h.id : rid(),
    name, area: txt(b.area, 100), phone: txt(b.phone, 30), lat, lng,
    registeredAt: h ? h.registeredAt : now,
    updatedAt: h ? h.updatedAt : 0,
    lastSeen: now,
    status: h ? h.status : cleanStatus({ icuTotal: 0, oxygenLevel: 'ok', oxygenAvailable: true, emergencyDoctor: true }, null),
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

const FRESH_MS = 6 * 3600 * 1000; // status older than 6 hours is shown as "old"

// What an ambulance driver needs: "can this hospital take a critical patient right now?"
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

function get(id) { return store.get('hospitals', String(id)); }
function remove(id) { return store.remove('hospitals', String(id)); }

module.exports = { SPECIALTIES, BLOOD, init, register, updateStatus, touch, live, view, get, remove, cleanStatus };

'use strict';
// Run: node test-features.js   (version 5 features, works offline)
const assert = require('assert');
const { spawn } = require('child_process');
const os = require('os');
const path = require('path');
const { triage } = require('./features');

// ---- pure triage rules ----
assert.strictEqual(triage({ spo2: 88 }).level, 'red', 'SpO2 below 90 is RED');
assert.strictEqual(triage({ spo2: 92 }).level, 'yellow', 'SpO2 90-93 is YELLOW');
assert.strictEqual(triage({ hr: 140 }).level, 'red', 'heart rate above 130 is RED');
assert.strictEqual(triage({ ecg: 'stemi' }).level, 'red', 'STEMI is RED');
assert.strictEqual(triage({ hr: 80, spo2: 98, bpSys: 120 }).level, 'green');

const PORT = 3998;
const BASE = 'http://127.0.0.1:' + PORT;
const env = { ...process.env, NODE_ENV: 'test', PORT: String(PORT), ADMIN_CODE: 'adm', DRIVER_CODE: 'drv', POLICE_CODE: 'pol', DATA_FILE: path.join(os.tmpdir(), 'amb-feat-' + Date.now() + '.json'), MONGODB_URI: '', OSRM_URL: 'http://127.0.0.1:9', NOMINATIM_URL: 'http://127.0.0.1:9', NTFY_ENABLED: '0' };
const call = async (method, p, body, headers = {}) => {
  const r = await fetch(BASE + p, { method, headers: { 'Content-Type': 'application/json', ...headers }, body: body ? JSON.stringify(body) : undefined });
  return { status: r.status, body: await r.json().catch(() => ({})) };
};
const D = { 'x-access-code': 'drv' }, A = { 'x-admin-code': 'adm' };

(async () => {
  const srv = spawn('node', ['server.js'], { env, stdio: ['ignore', 'pipe', 'pipe'] });
  await new Promise((res, rej) => { srv.stdout.on('data', (d) => String(d).includes('running on port') && res()); setTimeout(() => rej(new Error('timeout')), 8000); });
  try {
    // OTP login: demo mode returns the OTP, token works, wrong role is refused
    const rq = await call('POST', '/api/auth/otp/request', { phone: '+91 98765 43210', role: 'driver' });
    assert.strictEqual(rq.status, 200); assert.strictEqual(rq.body.mode, 'demo'); assert.ok(/^\d{6}$/.test(rq.body.demoOtp));
    assert.strictEqual((await call('POST', '/api/auth/otp/verify', { phone: '9876543210', role: 'driver', otp: '000000' })).status, 401, 'wrong OTP refused');
    const vf = await call('POST', '/api/auth/otp/verify', { phone: '9876543210', role: 'driver', otp: rq.body.demoOtp, name: 'Ravi', ambulanceId: 'br01' });
    assert.ok(vf.body.token);
    const T = { 'x-auth-token': vf.body.token };
    assert.strictEqual((await call('GET', '/api/auth/me', null, T)).body.user.ambulanceId, 'BR01');
    assert.strictEqual((await call('POST', '/api/posts/register', { lat: 25, lng: 85 }, T)).status, 403, 'driver token cannot use police API');
    assert.strictEqual((await call('POST', '/api/route', { from: { lat: 25.6, lng: 85.1 }, to: { lat: 25.62, lng: 85.12 } }, { 'x-auth-token': 'x'.repeat(30) })).status, 401);

    // hospitals: best hospital = specialty match, not only nearest
    const near = await call('POST', '/api/hospitals/register', { name: 'Near Clinic', lat: 25.601, lng: 85.101 }, D);
    await call('POST', `/api/hospitals/${near.body.hospital.id}/status`, { icuTotal: 4, icuAvailable: 0, oxygenLevel: 'none', emergencyDoctor: false, specialties: ['general'] }, D);
    const heart = await call('POST', '/api/hospitals/register', { name: 'Heart Hospital', lat: 25.63, lng: 85.13 }, D);
    await call('POST', `/api/hospitals/${heart.body.hospital.id}/status`, { icuTotal: 6, icuAvailable: 3, oxygenLevel: 'ok', emergencyDoctor: true, specialties: ['cardiac'] }, D);
    const best = await call('GET', '/api/hospitals/best?lat=25.6&lng=85.1&type=cardiac', null, D);
    assert.strictEqual(best.body.best.name, 'Heart Hospital', 'cardiac patient goes to the cardiac hospital with ICU, not the nearest');

    // trip + vitals + corridor + offline batch
    const st = await call('POST', '/api/trips/start', { ambulanceId: 'BR01', from: { lat: 25.6, lng: 85.1 }, to: { lat: 25.63, lng: 85.13 }, destinationName: 'Heart Hospital', mode: 'smooth', emergencyType: 'cardiac' }, T);
    assert.ok(st.body.tripId); assert.strictEqual(st.body.route.mode, 'smooth');
    const id = st.body.tripId;
    const v = await call('POST', `/api/trips/${id}/vitals`, { hr: 142, spo2: 87, bpSys: 85, ecg: 'stemi' }, T);
    assert.strictEqual(v.body.vitals.triage.level, 'red');
    const inc = await call('GET', `/api/hospitals/${heart.body.hospital.id}/incoming`, null, D);
    assert.strictEqual(inc.body.ambulances[0].vitals.triage.level, 'red', 'hospital sees live vitals');
    assert.strictEqual(inc.body.ambulances[0].emergencyType, 'cardiac');
    assert.ok(Array.isArray((await call('GET', `/api/trips/${id}/corridor`, null, D)).body.signals));
    const off = await call('POST', `/api/trips/${id}/locations`, { points: [{ lat: 25.605, lng: 85.105, t: 2 }, { lat: 25.602, lng: 85.102, t: 1 }] }, T);
    assert.strictEqual(off.body.accepted, 2);

    // railway gate closed -> route penalty is reported
    const rx = await call('POST', '/api/railway', { name: 'Gate 5', lat: 25.615, lng: 85.115 }, D);
    await call('POST', `/api/railway/${rx.body.crossing.id}/status`, { status: 'closed' }, D);
    const r2 = await call('POST', '/api/route', { from: { lat: 25.6, lng: 85.1 }, to: { lat: 25.63, lng: 85.13 } }, D);
    assert.strictEqual(r2.body.route.road.closedCrossings, 1, 'closed railway gate on route is detected');
    assert.strictEqual((await call('POST', '/api/road/bumps', { points: [{ lat: 25.61, lng: 85.11, g: 9 }, { lat: 25.61, lng: 85.11, g: 1 }] }, T)).body.saved, 1, 'small shakes ignored');

    // SOS
    const sos = await call('POST', '/api/sos', { lat: 25.61, lng: 85.11, type: 'trauma', note: 'Accident' });
    assert.ok(sos.body.id);
    const open = await call('GET', '/api/sos/open?lat=25.6&lng=85.1', null, D);
    assert.strictEqual(open.body.sos.length, 1);
    assert.strictEqual((await call('POST', `/api/sos/${sos.body.id}/accept`, { ambulanceId: 'BR01' }, D)).body.sos.status, 'assigned');
    assert.strictEqual((await call('POST', `/api/sos/${sos.body.id}/accept`, { ambulanceId: 'X' }, D)).status, 409, 'only one ambulance can accept');

    // admin live map + report + pages
    const live = await call('GET', '/api/admin/live', null, A);
    assert.strictEqual(live.body.trips.length, 1); assert.strictEqual(live.body.trips[0].triage.level, 'red');
    assert.strictEqual((await call('GET', '/api/admin/report', null, A)).body.ok, true);
    for (const pg of ['/admin/live', '/sos', '/er/abc']) assert.strictEqual((await fetch(BASE + pg)).status, 200, pg);
    assert.ok((await call('GET', '/api/push/topic?role=police&id=P1', null, D)).body.topic.startsWith('amburoute-p-'));

    console.log('features test: ALL PASSED');
  } finally { srv.kill(); }
})().catch((e) => { console.error('FAILED:', e); process.exit(1); });

'use strict';
// Run: node test-hospitals.js   (hospital live status + family tracking link, against the real server)
const assert = require('assert');
const { spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const PORT = 3998;
const BASE = 'http://127.0.0.1:' + PORT;
const file = path.join(os.tmpdir(), 'amburoute-hosp-' + Date.now() + '.json');
const CODE = 'Anisha_9631';
const env = { ...process.env, PORT: String(PORT), DATA_FILE: file, MONGODB_URI: '', OSRM_URL: 'http://127.0.0.1:9', NOMINATIM_URL: 'http://127.0.0.1:9', DRIVER_CODE: CODE, POLICE_CODE: CODE };

function start() {
  const p = spawn('node', ['server.js'], { env, stdio: ['ignore', 'pipe', 'pipe'] });
  return new Promise((resolve, reject) => {
    p.stdout.on('data', (d) => { if (String(d).includes('running on port')) resolve(p); });
    p.on('exit', (c) => reject(new Error('server exited ' + c)));
    setTimeout(() => reject(new Error('server start timeout')), 8000);
  });
}
const call = async (method, p, body, headers = { 'x-access-code': CODE }) => {
  const r = await fetch(BASE + p, { method, headers: { 'Content-Type': 'application/json', ...headers }, body: body ? JSON.stringify(body) : undefined });
  const ct = r.headers.get('content-type') || '';
  return { status: r.status, body: ct.includes('json') ? await r.json().catch(() => ({})) : await r.text() };
};

(async () => {
  const srv = await start();
  try {
    // access code is checked
    assert.strictEqual((await call('GET', '/api/hospitals/live', null, {})).status, 401, 'wrong/no code is refused');

    // hospital registers + sets status
    const reg = await call('POST', '/api/hospitals/register', { name: 'City Care Hospital', phone: '0612-111', lat: 25.21, lng: 85.53 });
    assert.strictEqual(reg.status, 200, JSON.stringify(reg.body));
    const hid = reg.body.hospital.id;
    assert.strictEqual(reg.body.hospital.ready, 'unknown', 'no status sent yet => unknown');
    const again = await call('POST', '/api/hospitals/register', { name: 'City Care Hospital', lat: 25.2101, lng: 85.5301 });
    assert.strictEqual(again.body.hospital.id, hid, 'same hospital is not duplicated');
    assert.strictEqual((await call('POST', '/api/hospitals/register', { name: 'x', lat: 1, lng: 1 })).status, 400);

    const up = await call('POST', `/api/hospitals/${hid}/status`, { icuTotal: 10, icuAvailable: 3, oxygenAvailable: true, oxygenLevel: 'ok', oxygenCylinders: 40, ventilatorsAvailable: 2, emergencyDoctor: true });
    assert.strictEqual(up.body.hospital.ready, 'ready');
    assert.strictEqual(up.body.hospital.icuAvailable, 3);

    const full = await call('POST', '/api/hospitals/register', { name: 'Far Hospital', lat: 25.3, lng: 85.6 });
    await call('POST', `/api/hospitals/${full.body.hospital.id}/status`, { icuTotal: 5, icuAvailable: 0, oxygenAvailable: false, oxygenLevel: 'none', emergencyDoctor: true });
    const live = await call('GET', '/api/hospitals/live?lat=25.2&lng=85.5');
    assert.strictEqual(live.body.hospitals[0].name, 'City Care Hospital', 'ready hospital is listed first');
    const far = live.body.hospitals.find((h) => h.name === 'Far Hospital');
    assert.strictEqual(far.ready, 'not_ready');
    assert.ok(far.problems.includes('No ICU bed') && far.problems.includes('No oxygen'));
    // oxygen "none" can never be saved as available
    assert.strictEqual(far.oxygenAvailable, false);
    const dir = await call('GET', '/api/hospitals/directory');
    assert.ok(dir.body.hospitals.some((h) => h.live && h.name === 'City Care Hospital'));

    // driver starts a trip to this hospital, books a bed -> hospital sees the ambulance
    const trip = await call('POST', '/api/trips/start', { ambulanceId: 'amb-7', driverName: 'Ravi Kumar', from: { lat: 25.2, lng: 85.5 }, to: { lat: 25.21, lng: 85.53 }, destinationName: 'City Care Hospital' });
    assert.strictEqual(trip.status, 200, JSON.stringify(trip.body));
    const tid = trip.body.tripId;
    await call('POST', `/api/trips/${tid}/bed-booking`, { hospitalId: hid, hospitalName: 'City Care Hospital', bedType: 'ICU Bed + Ventilator', patientBrief: 'Chest pain' });
    const inc = await call('GET', `/api/hospitals/${hid}/incoming`);
    assert.strictEqual(inc.body.ambulances.length, 1);
    assert.strictEqual(inc.body.ambulances[0].ambulanceId, 'AMB-7');
    assert.strictEqual(inc.body.ambulances[0].booking.bedType, 'ICU Bed + Ventilator');
    const farInc = await call('GET', `/api/hospitals/${full.body.hospital.id}/incoming`);
    assert.strictEqual(farInc.body.ambulances.length, 0, 'other hospital does not see it');

    // hospital replies -> driver sees it
    const rep = await call('POST', `/api/hospitals/${hid}/respond`, { tripId: tid, response: 'accepted' });
    assert.strictEqual(rep.body.reply.response, 'accepted');
    const loc = await call('POST', `/api/trips/${tid}/location`, { lat: 25.2005, lng: 85.505, speed: 10, accuracy: 5 });
    assert.strictEqual(loc.body.hospitalReply.response, 'accepted', 'driver GPS update carries the hospital reply');
    const st = await call('GET', `/api/trips/${tid}`);
    assert.strictEqual(st.body.hospitalReply.hospitalName, 'City Care Hospital');
    assert.strictEqual((await call('GET', `/api/trips/${tid}/bed-booking`)).body.reply.response, 'accepted');

    // family link
    const sh = await call('POST', `/api/trips/${tid}/share`, {});
    assert.strictEqual(sh.status, 200);
    assert.ok(sh.body.link.includes('/track/' + sh.body.token));
    assert.strictEqual((await call('POST', `/api/trips/${tid}/share`, {})).body.token, sh.body.token, 'same trip => same link');
    const pub = await call('GET', `/api/track/${sh.body.token}`, null, {}); // NO access code: family has none
    assert.strictEqual(pub.status, 200, JSON.stringify(pub.body));
    assert.strictEqual(pub.body.ambulanceId, 'AMB-7');
    assert.ok(Number.isFinite(pub.body.lat) && pub.body.route.length > 1);
    assert.ok(!('driverName' in pub.body), 'driver name is not public');
    const page = await call('GET', `/track/${sh.body.token}`, null, {});
    assert.strictEqual(page.status, 200);
    assert.ok(String(page.body).includes('LIVE AMBULANCE TRACKING'));
    assert.strictEqual((await call('GET', '/api/track/not-a-real-token', null, {})).status, 404);

    // a driver (not logged in) cannot create links
    assert.strictEqual((await call('POST', `/api/trips/${tid}/share`, {}, {})).status, 401);
    console.log('ALL HOSPITAL + TRACKING TESTS PASSED');
  } finally {
    srv.removeAllListeners('exit'); srv.kill('SIGTERM');
    setTimeout(() => { fs.rmSync(file, { force: true }); process.exit(process.exitCode || 0); }, 400);
  }
})().catch((e) => { console.error('FAILED:', e); process.exitCode = 1; });

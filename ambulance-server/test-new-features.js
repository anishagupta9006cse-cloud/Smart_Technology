'use strict';
const assert = require('assert');
const auth = require('./auth');
const trafficSignals = require('./traffic_signals');
const roadIntelligence = require('./road_intelligence');
const hospitals = require('./hospitals');
const engine = require('./engine');
const { Store } = require('./db');

(async () => {
  console.log('Testing new features...');

  // 1. Auth & OTP
  const otpRes = auth.sendOtp('9876543210', 'driver');
  assert.strictEqual(otpRes.ok, true);
  assert.strictEqual(otpRes.demoOtp, '1234');
  const verifyRes = auth.verifyOtp('9876543210', '1234', 'driver', { name: 'Ramesh Kumar', ambulanceId: 'AMB-101' });
  assert.strictEqual(verifyRes.ok, true);
  assert.strictEqual(verifyRes.user.ambulanceId, 'AMB-101');
  console.log('PASS: Auth & OTP system verified');

  // 2. Traffic Signals
  const signals = trafficSignals.getAllSignals();
  assert.ok(signals.length >= 4);
  // Ambulance near Hospital Gate Crossing (25.1995, 85.5210)
  const triggered = trafficSignals.evaluateSignalsForAmbulance('AMB-101', { lat: 25.1994, lng: 85.5209 });
  assert.ok(triggered.length >= 1);
  assert.strictEqual(triggered[0].currentState, 'GREEN');
  assert.strictEqual(triggered[0].greenCorridorActive, true);
  console.log('PASS: Traffic Signals & Dynamic Green Corridor verified');

  // 3. Road Intelligence
  const roads = roadIntelligence.analyzeRouteRoads([{ lat: 25.2, lng: 85.5 }], 'smooth');
  assert.strictEqual(roads.routeMode, 'SMOOTH_TRAUMA_SAFE');
  assert.strictEqual(roads.potholeRisk, 'LOW');
  assert.strictEqual(roads.railwayCrossingStatus, 'OPEN');
  console.log('PASS: Road Intelligence & Pothole/Railway analysis verified');

  // 4. Hospitals & AI Best Hospital recommendation
  const store = new Store();
  await store.init();
  hospitals.init(store);
  hospitals.register({ name: 'Apex Multi-Specialty', lat: 25.20, lng: 85.52, phone: '102' });
  hospitals.register({ name: 'Apollo Trauma & Cardiac', lat: 25.21, lng: 85.53, phone: '108' });

  const best = hospitals.recommendBestHospital({ near: { lat: 25.201, lng: 85.521 }, emergencyType: 'cardiac', routeMode: 'smooth' });
  assert.ok(best.bestHospital);
  assert.ok(best.bestHospital.aiScore > 50);
  assert.ok(best.bestHospital.matchPercentage.includes('%'));
  console.log('PASS: Auto Best Hospital AI scoring verified. Best:', best.bestHospital.name, best.bestHospital.matchPercentage);

  // 5. Patient Vitals on Trip
  const dummyRoute = {
    route: { total: 1000, points: [{ lat: 25.2, lng: 85.5 }, { lat: 25.21, lng: 85.51 }] },
    junctions: [],
    distance: 1000,
    duration: 120,
  };
  const trip = engine.startTrip({ driverName: 'Ramesh', ambulanceId: 'AMB-101', from: { lat: 25.2, lng: 85.5 }, to: { lat: 25.21, lng: 85.51 }, routeData: dummyRoute });
  const vitals = engine.setVitals(trip.id, {
    pulse: 110,
    spo2: 94,
    bpSys: 145,
    bpDia: 90,
    emergencyType: 'cardiac',
    triageSeverity: 'red',
  });
  assert.strictEqual(vitals.pulse, 110);
  assert.strictEqual(vitals.emergencyType, 'cardiac');

  const view = engine.tripView(trip);
  assert.strictEqual(view.patientVitals.pulse, 110);
  assert.strictEqual(view.patientVitals.emergencyType, 'cardiac');
  console.log('PASS: Patient Vitals Tele-Triage in Trip Model verified');

  console.log('\nALL NEW SERVER-SIDE MODULES & FEATURES FUNCTIONING PERFECTLY!');
  process.exit(0);
})();

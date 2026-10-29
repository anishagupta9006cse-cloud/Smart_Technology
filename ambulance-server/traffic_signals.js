'use strict';
// Smart Traffic Signals & Dynamic Green Corridor Engine
const { haversine } = require('./geo');

// Simulated traffic signals along major intersections
const DEFAULT_SIGNALS = [
  { id: 'SIG-101', name: 'Hospital Gate Crossing', lat: 25.1995, lng: 85.5210, normalState: 'RED', radius: 450 },
  { id: 'SIG-102', name: 'Station Road Chowk', lat: 25.1970, lng: 85.5180, normalState: 'RED', radius: 450 },
  { id: 'SIG-103', name: 'Civil Lines Junction', lat: 25.1940, lng: 85.5140, normalState: 'RED', radius: 450 },
  { id: 'SIG-104', name: 'Bypass Highway Circle', lat: 25.1910, lng: 85.5100, normalState: 'RED', radius: 450 },
  { id: 'SIG-105', name: 'Gandhi Maidan Crossing', lat: 25.1965, lng: 85.5165, normalState: 'RED', radius: 450 },
];

class TrafficSignalManager {
  constructor() {
    this.signals = new Map();
    DEFAULT_SIGNALS.forEach(s => {
      this.signals.set(s.id, {
        ...s,
        currentState: s.normalState,
        greenCorridorActive: false,
        activeAmbulanceId: null,
        overriddenAt: 0,
        distanceToAmbulance: null,
      });
    });
  }

  getAllSignals() {
    return Array.from(this.signals.values());
  }

  getSignal(id) {
    return this.signals.get(id);
  }

  // Called on ambulance location update to check geofence and trigger Green Corridor
  evaluateSignalsForAmbulance(ambulanceId, ambulancePos) {
    const affectedSignals = [];
    const now = Date.now();

    for (const signal of this.signals.values()) {
      const dist = haversine(ambulancePos, { lat: signal.lat, lng: signal.lng });
      
      // If ambulance is approaching within alert radius (e.g. 450m)
      if (dist <= signal.radius) {
        signal.currentState = 'GREEN';
        signal.greenCorridorActive = true;
        signal.activeAmbulanceId = ambulanceId;
        signal.overriddenAt = now;
        signal.distanceToAmbulance = Math.round(dist);
        affectedSignals.push({ ...signal });
      } else if (signal.activeAmbulanceId === ambulanceId && now - signal.overriddenAt > 60000) {
        // Auto-revert after 60s if ambulance moved away
        signal.currentState = signal.normalState;
        signal.greenCorridorActive = false;
        signal.activeAmbulanceId = null;
        signal.distanceToAmbulance = null;
      }
    }

    return affectedSignals;
  }

  // Manual override by traffic police or admin
  manualOverride(id, state, ambulanceId = 'MANUAL') {
    const s = this.signals.get(id);
    if (!s) return null;
    s.currentState = state;
    s.greenCorridorActive = state === 'GREEN';
    s.activeAmbulanceId = s.greenCorridorActive ? ambulanceId : null;
    s.overriddenAt = Date.now();
    return s;
  }
}

module.exports = new TrafficSignalManager();

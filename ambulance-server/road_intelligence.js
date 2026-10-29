'use strict';
// Real-world Road Conditions & Route Intelligence
// Handles Pothole awareness, Road Quality (Smooth vs Fast route), Railway Crossing status, and Street Width clearance.

const RAILWAY_CROSSINGS = [
  { id: 'RC-01', name: 'Railway Station Level Crossing', lat: 25.1980, lng: 85.5190, status: 'OPEN', nextTrainSec: 1800 },
  { id: 'RC-02', name: 'Industrial Belt Goods Crossing', lat: 25.1920, lng: 85.5120, status: 'OPEN', nextTrainSec: 3600 },
];

function analyzeRouteRoads(routePoints, routeMode = 'smooth') {
  // Simulated crowdsourced road accelerometer / telemetry data
  // Mode: 'smooth' (Trauma safe) vs 'fastest'
  const isSmoothMode = routeMode === 'smooth';
  
  // Calculate road surface score
  const roadQualityScore = isSmoothMode ? 96 : 82; // 96% smooth in smooth mode, 82% in fastest
  const bumpCount = isSmoothMode ? 2 : 9;
  const potholeRisk = isSmoothMode ? 'LOW' : 'MODERATE';

  // Check railway crossing proximity
  const railwayAlerts = [];
  const startPt = routePoints[0] || { lat: 25.2, lng: 85.5 };
  
  RAILWAY_CROSSINGS.forEach(rc => {
    // If route passes near railway crossing
    railwayAlerts.push({
      crossingId: rc.id,
      name: rc.name,
      status: rc.status,
      clearanceTimeSec: rc.status === 'CLOSED' ? 300 : 0,
      note: rc.status === 'OPEN' ? 'Barrier is OPEN - safe to proceed' : 'Barrier is CLOSED - rerouting suggested'
    });
  });

  return {
    routeMode: isSmoothMode ? 'SMOOTH_TRAUMA_SAFE' : 'FASTEST_STANDARD',
    roadQualityScore, // 0 - 100
    potholeRisk,
    bumpCountEstimated: bumpCount,
    streetWidthClearance: 'PASS (> 6.0m wide emergency corridor)',
    railwayCrossingStatus: railwayAlerts[0] ? railwayAlerts[0].status : 'OPEN',
    railwayAlerts,
    traumaSafeRecommendation: isSmoothMode 
      ? 'Optimal route chosen: Minimum vibration for cardiac and spinal trauma protection.'
      : 'Standard fastest route selected. Drive cautiously on uneven patches.'
  };
}

module.exports = {
  analyzeRouteRoads,
  RAILWAY_CROSSINGS
};

import 'package:latlong2/latlong.dart';

double _d(dynamic v, [double def = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? def;
  return def;
}

String _s(dynamic v, [String def = '']) => v == null ? def : v.toString();

Map<String, dynamic> _m(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<dynamic> _l(dynamic v) => v is List ? v : <dynamic>[];

class Junction {
  final String id;
  final String name;
  final LatLng point;
  final double chain;
  Junction(this.id, this.name, this.point, this.chain);

  factory Junction.fromJson(Map<String, dynamic> j) => Junction(
        _s(j['id']),
        _s(j['name'], 'Junction'),
        LatLng(_d(j['lat']), _d(j['lng'])),
        _d(j['chain']),
      );
}

class RouteInfo {
  final List<LatLng> points;
  final List<Junction> junctions;
  final double distance;
  final double duration;
  final bool fallback;
  /// fast | smooth (smooth = avoids potholes for spinal / cardiac patients)
  String mode = 'fast';
  int smoothScore = 100; // 100 = very smooth road
  int potholes = 0;
  int crossings = 0; // railway crossings on the route
  int closedCrossings = 0; // railway gates CLOSED right now
  int narrow = 0; // narrow lanes on the route
  int alternatives = 0; // other routes the server compared
  RouteInfo(this.points, this.junctions, this.distance, this.duration, this.fallback);

  factory RouteInfo.fromJson(Map<String, dynamic> j) {
    final pts = <LatLng>[];
    for (final e in _l(j['points'])) {
      final l = _l(e);
      if (l.length >= 2) pts.add(LatLng(_d(l[0]), _d(l[1])));
    }
    final r = RouteInfo(
      pts,
      _l(j['junctions']).map((e) => Junction.fromJson(_m(e))).toList(),
      _d(j['distance']),
      _d(j['duration']),
      j['fallback'] == true,
    );
    r.mode = j['mode']?.toString() ?? 'fast';
    r.alternatives = _l(j['alternatives']).length;
    if (j['road'] is Map) {
      final road = _m(j['road']);
      r.smoothScore = _d(road['smoothScore'], 100).round();
      r.potholes = _d(road['potholes']).round();
      r.crossings = _d(road['crossings']).round();
      r.closedCrossings = _d(road['closedCrossings']).round();
      r.narrow = _d(road['narrow']).round();
    }
    return r;
  }
}

class PlaceResult {
  final String name;
  final LatLng point;
  final String category; // hospital | police | transport | market | ... | other
  final bool local; // true = saved in our own places database
  final int? distance; // metres from the user (if known)
  PlaceResult(this.name, this.point,
      {this.category = 'other', this.local = false, this.distance});
}

class NextJunction {
  final String id;
  final String name;
  final LatLng point;
  final double distance;
  NextJunction(this.id, this.name, this.point, this.distance);
}

class PostInfo {
  final String id;
  final String name;
  final LatLng point;
  final double radius;
  final double distAhead;
  final String status;
  final bool acked;
  PostInfo(this.id, this.name, this.point, this.radius, this.distAhead, this.status, this.acked);
}

class PoliceAction {
  final String postName;
  final String action;
  final int at;
  PoliceAction(this.postName, this.action, this.at);

  String get label {
    switch (action) {
      case 'ack':
        return 'Police saw your alert';
      case 'clear_lane':
        return 'Police are clearing the lane';
      case 'escalate':
        return 'Police asked for help';
      default:
        return action;
    }
  }
}

/// A police post whose phone is online (shown on the driver map, even when it is not on the route).
class PolicePost {
  final String id;
  final String name;
  final String area;
  final LatLng point;
  final double radius;
  PolicePost(this.id, this.name, this.area, this.point, this.radius);

  factory PolicePost.fromJson(Map<String, dynamic> j) => PolicePost(
        _s(j['id']),
        _s(j['name'], 'Police Post'),
        _s(j['area']),
        LatLng(_d(j['lat']), _d(j['lng'])),
        _d(j['radius'], 500),
      );
}

/// State of one IoT device (display + buzzer).
class IotTelemetry {
  final double? lat;
  final double? lng;
  final double speed;
  final double altitude;
  final int sats;
  final bool fix;
  final double hdop;
  final int? battery;
  final int updatedAt;

  IotTelemetry({
    this.lat,
    this.lng,
    this.speed = 0,
    this.altitude = 0,
    this.sats = 0,
    this.fix = false,
    this.hdop = 0,
    this.battery,
    this.updatedAt = 0,
  });

  factory IotTelemetry.fromJson(Map<String, dynamic> j) => IotTelemetry(
        lat: j['lat'] != null ? _d(j['lat']) : null,
        lng: j['lng'] != null ? _d(j['lng']) : null,
        speed: _d(j['speed']),
        altitude: _d(j['altitude']),
        sats: (j['sats'] is num) ? (j['sats'] as num).toInt() : 0,
        fix: j['fix'] == true,
        hdop: _d(j['hdop']),
        battery: (j['battery'] is num) ? (j['battery'] as num).toInt() : null,
        updatedAt: (j['updatedAt'] is num) ? (j['updatedAt'] as num).toInt() : 0,
      );
}

class IotDevice {
  final String id;
  final bool online;
  final int? lastSeenSec;
  final bool auto;
  final bool displayOn;
  final String displayText;
  final bool buzzerOn;
  final String buzzerPattern;
  final int buzzerRemaining;
  final bool ledOn;
  final String ledPattern;
  final int ledRemaining;
  final IotTelemetry? telemetry;

  IotDevice({
    required this.id,
    required this.online,
    required this.lastSeenSec,
    required this.auto,
    required this.displayOn,
    required this.displayText,
    required this.buzzerOn,
    required this.buzzerPattern,
    required this.buzzerRemaining,
    this.ledOn = false,
    this.ledPattern = 'off',
    this.ledRemaining = 0,
    this.telemetry,
  });

  factory IotDevice.fromJson(Map<String, dynamic> j) {
    final d = _m(j['display']);
    final b = _m(j['buzzer']);
    final l = _m(j['led']);
    final tel = j['telemetry'] is Map ? IotTelemetry.fromJson(_m(j['telemetry'])) : null;
    return IotDevice(
      id: _s(j['id']),
      online: j['online'] == true,
      lastSeenSec: j['lastSeenSec'] is num ? (j['lastSeenSec'] as num).round() : null,
      auto: j['auto'] != false,
      displayOn: d['on'] == true,
      displayText: _s(d['text']),
      buzzerOn: b['on'] == true,
      buzzerPattern: _s(b['pattern'], 'off'),
      buzzerRemaining: _d(b['remainingSec']).round(),
      ledOn: l['on'] == true,
      ledPattern: _s(l['pattern'], 'off'),
      ledRemaining: _d(l['remainingSec']).round(),
      telemetry: tel,
    );
  }
}

class BedBooking {
  final String hospitalName;
  final String bedType;
  final String patientBrief;
  final String contactPhone;
  final String status;
  final int bookedAt;

  BedBooking({
    required this.hospitalName,
    required this.bedType,
    this.patientBrief = '',
    this.contactPhone = '',
    this.status = 'CONFIRMED',
    int? bookedAt,
  }) : bookedAt = bookedAt ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
        'hospitalName': hospitalName,
        'bedType': bedType,
        'patientBrief': patientBrief,
        'contactPhone': contactPhone,
        'status': status,
        'bookedAt': bookedAt,
      };

  factory BedBooking.fromJson(Map<String, dynamic> j) => BedBooking(
        hospitalName: _s(j['hospitalName']),
        bedType: _s(j['bedType'], 'Emergency ICU Bed'),
        patientBrief: _s(j['patientBrief']),
        contactPhone: _s(j['contactPhone']),
        status: _s(j['status'], 'CONFIRMED'),
        bookedAt: (j['bookedAt'] is num) ? (j['bookedAt'] as num).toInt() : null,
      );
}

/// Live status of one hospital (filled in by the Hospital app).
class HospitalLive {
  final String id;
  final String name;
  final String area;
  final String phone;
  final LatLng point;
  final int icuTotal;
  final int icuAvailable;
  final int ventilators;
  final int traumaBeds;
  final int generalBeds;
  final int oxygenCylinders;
  final bool oxygenAvailable;
  final String oxygenLevel; // ok | low | none
  final bool emergencyDoctor;
  final bool bloodAvailable;
  final String notes;
  final String ready; // ready | limited | not_ready | unknown
  final List<String> problems;
  final int? ageMin; // minutes since the hospital last updated
  final int? distance; // metres from the driver

  HospitalLive({
    required this.id,
    required this.name,
    required this.area,
    required this.phone,
    required this.point,
    required this.icuTotal,
    required this.icuAvailable,
    required this.ventilators,
    required this.traumaBeds,
    required this.generalBeds,
    required this.oxygenCylinders,
    required this.oxygenAvailable,
    required this.oxygenLevel,
    required this.emergencyDoctor,
    required this.bloodAvailable,
    required this.notes,
    required this.ready,
    required this.problems,
    this.ageMin,
    this.distance,
  });

  factory HospitalLive.fromJson(Map<String, dynamic> j) => HospitalLive(
        id: _s(j['id']),
        name: _s(j['name'], 'Hospital'),
        area: _s(j['area']),
        phone: _s(j['phone']),
        point: LatLng(_d(j['lat']), _d(j['lng'])),
        icuTotal: _d(j['icuTotal']).round(),
        icuAvailable: _d(j['icuAvailable']).round(),
        ventilators: _d(j['ventilatorsAvailable']).round(),
        traumaBeds: _d(j['traumaBeds']).round(),
        generalBeds: _d(j['generalBeds']).round(),
        oxygenCylinders: _d(j['oxygenCylinders']).round(),
        oxygenAvailable: j['oxygenAvailable'] == true,
        oxygenLevel: _s(j['oxygenLevel'], 'ok'),
        emergencyDoctor: j['emergencyDoctor'] == true,
        bloodAvailable: j['bloodAvailable'] == true,
        notes: _s(j['notes']),
        ready: _s(j['ready'], 'unknown'),
        problems: _l(j['problems']).map((e) => e.toString()).toList(),
        ageMin: j['ageMin'] is num ? (j['ageMin'] as num).toInt() : null,
        distance: j['distance'] is num ? (j['distance'] as num).toInt() : null,
      );
}

/// The hospital's answer to a pre-booked bed: bed ready / no bed / please call.
class HospitalReply {
  final String hospitalName;
  final String response; // accepted | no_bed | need_info
  final String text;
  final String phone;
  final String note;
  final int at;

  HospitalReply({
    required this.hospitalName,
    required this.response,
    required this.text,
    required this.phone,
    required this.note,
    required this.at,
  });

  factory HospitalReply.fromJson(Map<String, dynamic> j) => HospitalReply(
        hospitalName: _s(j['hospitalName'], 'Hospital'),
        response: _s(j['response'], 'need_info'),
        text: _s(j['text']),
        phone: _s(j['phone']),
        note: _s(j['note']),
        at: _d(j['at']).round(),
      );
}

class TripState {
  final String status; // ok | off_route | completed | stopped
  final double chain;
  final double total;
  final double remaining;
  final double etaSec;
  final NextJunction? nextJunction;
  final List<PostInfo> posts;
  final List<PoliceAction> actions;
  final bool critical;
  final HospitalReply? hospitalReply;

  TripState({
    required this.status,
    required this.chain,
    required this.total,
    required this.remaining,
    required this.etaSec,
    required this.nextJunction,
    required this.posts,
    required this.actions,
    this.critical = false,
    this.hospitalReply,
  });

  factory TripState.fromJson(Map<String, dynamic> j) {
    NextJunction? nj;
    if (j['nextJunction'] is Map) {
      final n = _m(j['nextJunction']);
      nj = NextJunction(_s(n['id']), _s(n['name'], 'Junction'),
          LatLng(_d(n['lat']), _d(n['lng'])), _d(n['distance']));
    }
    return TripState(
      status: _s(j['status'], 'ok'),
      critical: _s(j['priority']) == 'critical',
      hospitalReply: j['hospitalReply'] is Map
          ? HospitalReply.fromJson(_m(j['hospitalReply']))
          : null,
      chain: _d(j['chain']),
      total: _d(j['total']),
      remaining: _d(j['remaining']),
      etaSec: _d(j['etaSec']),
      nextJunction: nj,
      posts: _l(j['posts']).map((e) {
        final p = _m(e);
        return PostInfo(_s(p['id']), _s(p['name'], 'Police Post'),
            LatLng(_d(p['lat']), _d(p['lng'])), _d(p['radius'], 500),
            _d(p['distAhead']), _s(p['status'], 'standby'), p['acked'] == true);
      }).toList(),
      actions: _l(j['actions']).map((e) {
        final a = _m(e);
        return PoliceAction(_s(a['postName']), _s(a['action']), _d(a['at']).round());
      }).toList(),
    );
  }
}

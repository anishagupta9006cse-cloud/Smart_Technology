double _d(dynamic v, [double def = 0]) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? def;
}

String _s(dynamic v, [String def = '']) => v == null ? def : v.toString();

/// What the hospital tells ambulance drivers: beds, oxygen, doctors.
class HospitalStatus {
  int icuTotal;
  int icuAvailable;
  int ventilators;
  int traumaBeds;
  int generalBeds;
  int oxygenCylinders;
  String oxygenLevel; // ok | low | none
  bool emergencyDoctor;
  bool bloodAvailable;
  String notes;
  List<String> specialties; // cardiac, trauma, stroke, burn, neuro, pediatric, maternity, general
  List<String> bloodGroups; // A+, O-, ...

  HospitalStatus({
    this.icuTotal = 0,
    this.icuAvailable = 0,
    this.ventilators = 0,
    this.traumaBeds = 0,
    this.generalBeds = 0,
    this.oxygenCylinders = 0,
    this.oxygenLevel = 'ok',
    this.emergencyDoctor = true,
    this.bloodAvailable = false,
    this.notes = '',
    List<String>? specialties,
    List<String>? bloodGroups,
  })  : specialties = specialties ?? ['trauma'],
        bloodGroups = bloodGroups ?? [];

  bool get oxygenAvailable => oxygenLevel != 'none';

  Map<String, dynamic> toJson() => {
        'icuTotal': icuTotal,
        'icuAvailable': icuAvailable,
        'ventilatorsAvailable': ventilators,
        'traumaBeds': traumaBeds,
        'generalBeds': generalBeds,
        'oxygenCylinders': oxygenCylinders,
        'oxygenLevel': oxygenLevel,
        'oxygenAvailable': oxygenAvailable,
        'emergencyDoctor': emergencyDoctor,
        'bloodAvailable': bloodAvailable,
        'notes': notes,
        'specialties': specialties,
        'bloodGroups': bloodGroups,
      };

  factory HospitalStatus.fromJson(Map<String, dynamic> j) => HospitalStatus(
        icuTotal: _d(j['icuTotal']).round(),
        icuAvailable: _d(j['icuAvailable']).round(),
        ventilators: _d(j['ventilatorsAvailable']).round(),
        traumaBeds: _d(j['traumaBeds']).round(),
        generalBeds: _d(j['generalBeds']).round(),
        oxygenCylinders: _d(j['oxygenCylinders']).round(),
        oxygenLevel: _s(j['oxygenLevel'], 'ok'),
        emergencyDoctor: j['emergencyDoctor'] != false,
        bloodAvailable: j['bloodAvailable'] == true,
        notes: _s(j['notes']),
        specialties: j['specialties'] is List ? (j['specialties'] as List).map((e) => e.toString()).toList() : null,
        bloodGroups: j['bloodGroups'] is List ? (j['bloodGroups'] as List).map((e) => e.toString()).toList() : null,
      );
}

/// An ambulance that is driving to this hospital.
class IncomingAmbulance {
  final String tripId;
  final String ambulanceId;
  final String driverName;
  final bool critical;
  final String message;
  final double remaining; // metres
  final double etaSec;
  final int speedKmh;
  final String bedType;
  final String patientBrief;
  final String contactPhone;
  final String reply; // accepted | no_bed | need_info | '' (no answer yet)
  final String emergencyType; // cardiac | trauma | stroke | burn | ...
  final String patientInfo; // age, gender, blood group, complaint
  final PatientVitals? vitals; // live vitals from the ambulance (tele-triage)

  IncomingAmbulance({
    required this.tripId,
    required this.ambulanceId,
    required this.driverName,
    required this.critical,
    required this.message,
    required this.remaining,
    required this.etaSec,
    required this.speedKmh,
    required this.bedType,
    required this.patientBrief,
    required this.contactPhone,
    required this.reply,
    this.emergencyType = 'general',
    this.patientInfo = '',
    this.vitals,
  });

  factory IncomingAmbulance.fromJson(Map<String, dynamic> j) {
    final b = j['booking'] is Map ? Map<String, dynamic>.from(j['booking'] as Map) : <String, dynamic>{};
    final m = j['message'] is Map ? Map<String, dynamic>.from(j['message'] as Map) : <String, dynamic>{};
    final r = j['reply'] is Map ? Map<String, dynamic>.from(j['reply'] as Map) : <String, dynamic>{};
    return IncomingAmbulance(
      tripId: _s(j['tripId']),
      ambulanceId: _s(j['ambulanceId'], 'AMB'),
      driverName: _s(j['driverName']),
      critical: _s(j['priority']) == 'critical',
      message: _s(m['text']),
      remaining: _d(j['remaining']),
      etaSec: _d(j['etaSec']),
      speedKmh: _d(j['speedKmh']).round(),
      bedType: _s(b['bedType']),
      patientBrief: _s(b['patientBrief']),
      contactPhone: _s(b['contactPhone']),
      reply: _s(r['response']),
      emergencyType: _s(j['emergencyType'], 'general'),
      patientInfo: _patient(j['patient']),
      vitals: j['vitals'] is Map ? PatientVitals.fromJson(Map<String, dynamic>.from(j['vitals'] as Map)) : null,
    );
  }
}

String _patient(dynamic p) {
  if (p is! Map) return '';
  final parts = <String>[];
  if (p['age'] != null) parts.add('${(p['age'] as num?)?.round() ?? p['age']} yrs');
  if ((p['gender'] ?? '').toString().isNotEmpty) parts.add(p['gender'].toString());
  if ((p['bloodGroup'] ?? '').toString().isNotEmpty) parts.add('Blood ${p['bloodGroup']}');
  if ((p['complaint'] ?? '').toString().isNotEmpty) parts.add(p['complaint'].toString());
  return parts.join(' • ');
}

/// Live patient vitals sent by the paramedic (or the IoT monitor) from inside the ambulance.
class PatientVitals {
  final double? hr, spo2, bpSys, bpDia, rr, temp, gcs;
  final String ecg;
  final String level; // red | yellow | green
  final List<String> flags;
  final String source;
  final int at;
  PatientVitals({this.hr, this.spo2, this.bpSys, this.bpDia, this.rr, this.temp, this.gcs,
      this.ecg = '', this.level = 'green', this.flags = const [], this.source = '', this.at = 0});

  static double? _n(dynamic v) => v is num ? v.toDouble() : null;

  factory PatientVitals.fromJson(Map<String, dynamic> j) {
    final t = j['triage'] is Map ? Map<String, dynamic>.from(j['triage'] as Map) : <String, dynamic>{};
    return PatientVitals(
      hr: _n(j['hr']), spo2: _n(j['spo2']), bpSys: _n(j['bpSys']), bpDia: _n(j['bpDia']),
      rr: _n(j['rr']), temp: _n(j['temp']), gcs: _n(j['gcs']),
      ecg: _s(j['ecg']), level: _s(t['level'], 'green'),
      flags: t['flags'] is List ? (t['flags'] as List).map((e) => e.toString()).toList() : const [],
      source: _s(j['source']), at: _d(j['at']).round(),
    );
  }
}

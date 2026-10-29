double _d(dynamic v, [double def = 0]) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? def;
}

String _s(dynamic v, [String def = '']) => v == null ? def : v.toString();

/// What the hospital tells ambulance drivers: beds, oxygen, doctors, specialty units.
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
  bool cathLab;
  bool ctScan;
  bool burnUnit;
  String notes;

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
    this.cathLab = true,
    this.ctScan = true,
    this.burnUnit = false,
    this.notes = '',
  });

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
        'cathLab': cathLab,
        'ctScan': ctScan,
        'burnUnit': burnUnit,
        'notes': notes,
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
        cathLab: j['cathLab'] != false,
        ctScan: j['ctScan'] != false,
        burnUnit: j['burnUnit'] == true,
        notes: _s(j['notes']),
      );
}

class IncomingVitals {
  final int pulse;
  final int spo2;
  final int bpSys;
  final int bpDia;
  final int respRate;
  final String bloodGroup;
  final String emergencyType;
  final String triageSeverity;
  final String notes;

  IncomingVitals({
    this.pulse = 0,
    this.spo2 = 0,
    this.bpSys = 0,
    this.bpDia = 0,
    this.respRate = 0,
    this.bloodGroup = '',
    this.emergencyType = '',
    this.triageSeverity = '',
    this.notes = '',
  });

  factory IncomingVitals.fromJson(Map<String, dynamic> j) => IncomingVitals(
        pulse: (j['pulse'] is num) ? (j['pulse'] as num).toInt() : 0,
        spo2: (j['spo2'] is num) ? (j['spo2'] as num).toInt() : 0,
        bpSys: (j['bpSys'] is num) ? (j['bpSys'] as num).toInt() : 0,
        bpDia: (j['bpDia'] is num) ? (j['bpDia'] as num).toInt() : 0,
        respRate: (j['respRate'] is num) ? (j['respRate'] as num).toInt() : 0,
        bloodGroup: _s(j['bloodGroup']),
        emergencyType: _s(j['emergencyType']),
        triageSeverity: _s(j['triageSeverity']),
        notes: _s(j['notes']),
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
  final IncomingVitals? vitals;

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
    this.vitals,
  });

  factory IncomingAmbulance.fromJson(Map<String, dynamic> j) {
    final b = j['booking'] is Map ? Map<String, dynamic>.from(j['booking'] as Map) : <String, dynamic>{};
    final m = j['message'] is Map ? Map<String, dynamic>.from(j['message'] as Map) : <String, dynamic>{};
    final r = j['reply'] is Map ? Map<String, dynamic>.from(j['reply'] as Map) : <String, dynamic>{};
    final v = j['patientVitals'] is Map ? IncomingVitals.fromJson(Map<String, dynamic>.from(j['patientVitals'] as Map)) : null;
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
      vitals: v,
    );
  }
}

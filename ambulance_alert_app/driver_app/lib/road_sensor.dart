import 'dart:async';
import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'api.dart';

/// Pothole detector (crowdsourced road quality).
/// While the ambulance drives, the phone accelerometer feels every bump.
/// Big shocks are sent to the server with the GPS position. The server uses them to suggest the
/// SMOOTHEST route for spinal-injury and cardiac patients.
class RoadSensor {
  RoadSensor._();
  static final RoadSensor I = RoadSensor._();

  StreamSubscription<UserAccelerometerEvent>? _sub;
  Timer? _flushTimer;
  final List<Map<String, dynamic>> _bumps = [];
  LatLng? Function()? _pos;
  double Function()? _speed;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  int detected = 0;

  bool get running => _sub != null;

  void start({required LatLng? Function() position, required double Function() speed}) {
    if (_sub != null) return;
    _pos = position;
    _speed = speed;
    try {
      _sub = userAccelerometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen(_onEvent, onError: (_) {});
    } catch (_) {
      _sub = null;
      return;
    }
    _flushTimer = Timer.periodic(const Duration(seconds: 30), (_) => flush());
  }

  void _onEvent(UserAccelerometerEvent e) {
    // userAccelerometer = movement without gravity. A pothole gives a short, strong shock.
    final g = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    if (g < 6) return; // normal driving
    final sp = _speed?.call() ?? 0;
    if (sp < 3) return; // standing still (phone in hand, door closing...)
    final now = DateTime.now();
    if (now.difference(_last).inMilliseconds < 1500) return; // one bump = one report
    final p = _pos?.call();
    if (p == null) return;
    _last = now;
    detected++;
    _bumps.add({'lat': p.latitude, 'lng': p.longitude, 'g': double.parse(g.toStringAsFixed(1))});
    if (_bumps.length > 200) _bumps.removeAt(0);
  }

  Future<void> flush() async {
    if (_bumps.isEmpty) return;
    final batch = List<Map<String, dynamic>>.from(_bumps);
    try {
      await Api.I.raw('POST', '/api/road/bumps', body: {'points': batch});
      _bumps.removeRange(0, batch.length.clamp(0, _bumps.length));
    } catch (_) {
      // keep them, try again later
    }
  }

  void stop() {
    flush();
    _sub?.cancel();
    _sub = null;
    _flushTimer?.cancel();
    _flushTimer = null;
  }
}

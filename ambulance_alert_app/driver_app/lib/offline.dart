import 'dart:convert';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'models.dart';

/// Offline mode.
/// - The last route is saved on the phone, so the map still shows it without network.
/// - GPS points that could not be sent are kept (also after an app restart) and sent together
///   as soon as the network is back, so police / hospital / family see the real path.
class OfflineQueue {
  OfflineQueue._();
  static final OfflineQueue I = OfflineQueue._();

  final List<Map<String, dynamic>> _points = [];
  String? _tripId;
  bool _flushing = false;

  int get pending => _points.length;

  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _tripId = sp.getString('offline_trip');
      final raw = sp.getString('offline_points');
      if (raw != null) {
        final l = jsonDecode(raw);
        if (l is List) _points.addAll(l.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('offline_points', jsonEncode(_points));
      if (_tripId != null) await sp.setString('offline_trip', _tripId!);
    } catch (_) {}
  }

  /// Saves one GPS point that could not be sent.
  void add(String tripId, LatLng p, double speed, double acc) {
    if (_tripId != tripId) {
      _points.clear();
      _tripId = tripId;
    }
    _points.add({
      'lat': p.latitude,
      'lng': p.longitude,
      'speed': speed,
      'acc': acc,
      't': DateTime.now().millisecondsSinceEpoch,
    });
    if (_points.length > 600) _points.removeRange(0, _points.length - 600); // ~20 min at 2 s
    _save();
  }

  /// Sends all saved points. Returns the new trip state, or null if nothing was sent.
  Future<TripState?> flush(String tripId) async {
    if (_flushing || _points.isEmpty) return null;
    if (_tripId != tripId) {
      clear();
      return null;
    }
    _flushing = true;
    try {
      final batch = List<Map<String, dynamic>>.from(_points);
      final res = await Api.I.raw('POST', '/api/trips/$tripId/locations', body: {'points': batch});
      _points.removeRange(0, batch.length.clamp(0, _points.length));
      _save();
      return TripState.fromJson(res);
    } catch (_) {
      return null;
    } finally {
      _flushing = false;
    }
  }

  void clear() {
    _points.clear();
    _tripId = null;
    SharedPreferences.getInstance().then((sp) {
      sp.remove('offline_points');
      sp.remove('offline_trip');
    }).catchError((_) {});
  }

  // ---- last route (so the map works offline) ----
  static Future<void> saveRoute(RouteInfo r, LatLng to, String toLabel) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
          'last_route',
          jsonEncode({
            'points': r.points.map((p) => [p.latitude, p.longitude]).toList(),
            'distance': r.distance,
            'duration': r.duration,
            'to': [to.latitude, to.longitude],
            'toLabel': toLabel,
            'savedAt': DateTime.now().millisecondsSinceEpoch,
          }));
    } catch (_) {}
  }

  /// (route, destination, label) of the last route, or null.
  static Future<(RouteInfo, LatLng, String)?> loadRoute() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('last_route');
      if (raw == null) return null;
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      final r = RouteInfo.fromJson({
        'points': j['points'],
        'junctions': const [],
        'distance': j['distance'],
        'duration': j['duration'],
        'fallback': false,
      });
      final to = j['to'] as List;
      return (r, LatLng((to[0] as num).toDouble(), (to[1] as num).toDouble()), j['toLabel']?.toString() ?? '');
    } catch (_) {
      return null;
    }
  }
}

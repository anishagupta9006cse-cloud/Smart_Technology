import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'models.dart';
import 'profile.dart';

class ApiException implements Exception {
  final String message;
  final int? status;
  final String? code;
  ApiException(this.message, {this.status, this.code});
  @override
  String toString() => message;
}

class Api {
  Api._();
  static final Api I = Api._();

  String baseUrl = AppConfig.defaultServer;
  String accessCode = AppConfig.defaultAccessCode;

  void configure(String? url, String? code) {
    var u = (url ?? '').trim();
    if (u.isEmpty) u = AppConfig.defaultServer;
    if (!u.startsWith('http')) u = 'https://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    baseUrl = u;
    final c = (code ?? '').trim();
    accessCode = c.isEmpty ? AppConfig.defaultAccessCode : c;
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (accessCode.isNotEmpty) 'x-access-code': accessCode,
      };

  Uri _u(String path) => Uri.parse('$baseUrl$path');

  /// The free Render server sleeps; the first request can take 30-60 seconds.
  Future<bool> wakeServer({int tries = 8}) async {
    for (var i = 0; i < tries; i++) {
      try {
        final r = await http.get(_u('/health')).timeout(const Duration(seconds: 20));
        if (r.statusCode == 200) return true;
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 3));
    }
    return false;
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 25),
    int retries = 2,
  }) async {
    ApiException? last;
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        final uri = _u(path);
        final http.Response res = method == 'GET'
            ? await http.get(uri, headers: _headers).timeout(timeout)
            : await http
                .post(uri, headers: _headers, body: jsonEncode(body ?? <String, dynamic>{}))
                .timeout(timeout);
        dynamic data;
        try {
          data = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body);
        } catch (_) {
          data = <String, dynamic>{};
        }
        final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
        if (res.statusCode >= 200 && res.statusCode < 300) return map;
        final msg = map['error']?.toString() ?? 'Server error (${res.statusCode})';
        final err = ApiException(msg, status: res.statusCode, code: map['code']?.toString());
        if (res.statusCode >= 500 && attempt < retries) {
          last = err;
          await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
          continue;
        }
        throw err;
      } on ApiException {
        rethrow;
      } catch (_) {
        last = ApiException('Cannot reach the server. Check your internet connection.');
        if (attempt < retries) await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }
    throw last ?? ApiException('Unknown error');
  }

  Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  /// Registers the hospital (or finds it again). Returns the hospital id.
  Future<String> register(HospitalProfile p) async {
    final res = await _send('POST', '/api/hospitals/register',
        body: {
          if (p.id.isNotEmpty) 'id': p.id,
          'name': p.name,
          'phone': p.phone,
          'area': p.area,
          'lat': p.lat,
          'lng': p.lng,
        },
        timeout: const Duration(seconds: 30));
    final id = _map(res['hospital'])['id']?.toString() ?? '';
    if (id.isEmpty) throw ApiException('The server did not accept this hospital. Please try again.');
    return id;
  }

  /// Status saved on the server + time of the last update (milliseconds, 0 = never).
  Future<(HospitalStatus, int)> getStatus(String id) async {
    final res = await _send('GET', '/api/hospitals/${Uri.encodeComponent(id)}',
        timeout: const Duration(seconds: 15), retries: 1);
    final h = _map(res['hospital']);
    final at = h['updatedAt'];
    return (HospitalStatus.fromJson(h), at is num ? at.toInt() : 0);
  }

  /// Saves the status. Returns the time of the update (milliseconds).
  Future<int> updateStatus(String id, HospitalStatus s) async {
    final res = await _send('POST', '/api/hospitals/${Uri.encodeComponent(id)}/status',
        body: s.toJson(), timeout: const Duration(seconds: 15), retries: 2);
    final at = _map(res['hospital'])['updatedAt'];
    return at is num ? at.toInt() : DateTime.now().millisecondsSinceEpoch;
  }

  Future<List<IncomingAmbulance>> incoming(String id) async {
    final res = await _send('GET', '/api/hospitals/${Uri.encodeComponent(id)}/incoming',
        timeout: const Duration(seconds: 10), retries: 0);
    final list = res['ambulances'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => IncomingAmbulance.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// response: accepted | no_bed | need_info
  Future<void> respond(String id, String tripId, String response, {String note = ''}) async {
    await _send('POST', '/api/hospitals/${Uri.encodeComponent(id)}/respond',
        body: {'tripId': tripId, 'response': response, 'note': note},
        timeout: const Duration(seconds: 10),
        retries: 1);
  }
}

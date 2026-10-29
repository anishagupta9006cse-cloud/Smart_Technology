import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

class HospitalProfile {
  final String id; // given by the server
  final String name;
  final String phone;
  final String area;
  final double lat;
  final double lng;
  final String accessCode;
  final String serverUrl;

  const HospitalProfile({
    required this.id,
    required this.name,
    required this.phone,
    required this.area,
    required this.lat,
    required this.lng,
    required this.accessCode,
    required this.serverUrl,
  });

  HospitalProfile withId(String newId) => HospitalProfile(
        id: newId,
        name: name,
        phone: phone,
        area: area,
        lat: lat,
        lng: lng,
        accessCode: accessCode,
        serverUrl: serverUrl,
      );

  static String _fixCode(String? saved) {
    final c = (saved ?? '').trim();
    return c.isEmpty ? AppConfig.defaultAccessCode : c;
  }

  static String _fixUrl(String? saved) {
    final u = (saved ?? '').trim();
    return u.isEmpty ? AppConfig.defaultServer : u;
  }

  static Future<HospitalProfile?> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final id = sp.getString('hospitalId') ?? '';
      final lat = sp.getDouble('lat');
      final lng = sp.getDouble('lng');
      if (id.isEmpty || lat == null || lng == null) return null;
      return HospitalProfile(
        id: id,
        name: sp.getString('name') ?? 'Hospital',
        phone: sp.getString('phone') ?? '',
        area: sp.getString('area') ?? '',
        lat: lat,
        lng: lng,
        accessCode: _fixCode(sp.getString('accessCode')),
        serverUrl: _fixUrl(sp.getString('serverUrl')),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('hospitalId', id);
    await sp.setString('name', name);
    await sp.setString('phone', phone);
    await sp.setString('area', area);
    await sp.setDouble('lat', lat);
    await sp.setDouble('lng', lng);
    await sp.setString('accessCode', accessCode);
    await sp.setString('serverUrl', serverUrl);
  }

  static Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove('hospitalId');
  }
}

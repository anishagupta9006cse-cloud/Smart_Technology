import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

class Profile {
  final String name;
  final String ambulanceId;
  final String accessCode;
  final String serverUrl;

  const Profile({
    required this.name,
    required this.ambulanceId,
    required this.accessCode,
    required this.serverUrl,
  });

  /// Phones that saved an old default address are moved to the new default.
  static String _fixUrl(String? saved) {
    final raw = (saved ?? '').trim();
    final u = raw.replaceAll(RegExp(r'/+$'), '');
    if (u.isEmpty || AppConfig.oldDefaultServers.contains(u)) {
      return AppConfig.defaultServer;
    }
    return raw;
  }

  /// An empty saved access code is replaced by the default one.
  static String _fixCode(String? saved) {
    final c = (saved ?? '').trim();
    return c.isEmpty ? AppConfig.defaultAccessCode : c;
  }

  static Future<Profile?> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final n = sp.getString('name') ?? '';
      if (n.isEmpty) return null;
      return Profile(
        name: n,
        ambulanceId: sp.getString('ambulanceId') ?? '',
        accessCode: _fixCode(sp.getString('accessCode')),
        serverUrl: _fixUrl(sp.getString('serverUrl')),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('name', name);
    await sp.setString('ambulanceId', ambulanceId);
    await sp.setString('accessCode', accessCode);
    await sp.setString('serverUrl', serverUrl);
  }

  static Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove('name');
  }
}

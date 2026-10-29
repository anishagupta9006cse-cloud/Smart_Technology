import 'package:latlong2/latlong.dart';

class AppConfig {
  /// Server URL. It can also be changed under "Advanced" on the login screen.
  static const String defaultServer = String.fromEnvironment(
    'SERVER_URL',
    defaultValue: 'https://smart-technology-ndw9.onrender.com',
  );
  /// Access code is filled in automatically, so nobody has to type it.
  /// (It is inside the APK, so only give the APK to people you trust.)
  static const String defaultAccessCode = String.fromEnvironment(
    'ACCESS_CODE',
    defaultValue: 'Anisha_9631',
  );
  static const String tileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  /// Old default addresses. If a phone saved one of them earlier, the app switches it to the new default automatically.
  static const List<String> oldDefaultServers = [
    'https://ambulance-alert-app.onrender.com',
    'https://smart-ambulance-mk2n.onrender.com',
  ];
  static const String packageName = 'com.amburoute.police';
  static const LatLng indiaCenter = LatLng(22.9734, 78.6569);
}

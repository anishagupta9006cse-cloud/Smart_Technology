class AppConfig {
  /// Server URL. It can also be changed under "Settings" on the setup screen.
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

  static const String packageName = 'com.amburoute.hospital';
}

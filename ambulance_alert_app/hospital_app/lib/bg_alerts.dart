import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';

/// Alerts even when the app is closed.
///
/// 1. A small Android background service keeps running (shows a notification "AmbuRoute is watching").
///    Every 8 seconds it asks the server for new alerts. A new ambulance -> loud notification + voice.
/// 2. Extra (optional): free "ntfy" push. Install the ntfy app and subscribe to the topic shown by
///    [openPushSetup]. Then alerts ring even if the phone killed AmbuRoute completely.
class BgAlerts {
  /// role: 'police' (id = post id) or 'hospital' (id = hospital id)
  static Future<void> start({required String role, required String id, required String name}) async {
    try {
      final perm = await FlutterForegroundTask.checkNotificationPermission();
      if (perm != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'amburoute_alerts',
          channelName: 'Ambulance alerts',
          channelDescription: 'Alerts about ambulances, also when the app is closed',
          channelImportance: NotificationChannelImportance.HIGH,
          priority: NotificationPriority.HIGH,
          playSound: true,
          enableVibration: true,
          onlyAlertOnce: false,
        ),
        iosNotificationOptions: const IOSNotificationOptions(showNotification: true, playSound: true),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.repeat(8000),
          autoRunOnBoot: true,
          autoRunOnMyPackageReplaced: true,
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );
      await FlutterForegroundTask.saveData(key: 'role', value: role);
      await FlutterForegroundTask.saveData(key: 'id', value: id);
      await FlutterForegroundTask.saveData(key: 'base', value: Api.I.baseUrl);
      await FlutterForegroundTask.saveData(key: 'code', value: Api.I.accessCode);
      await FlutterForegroundTask.saveData(key: 'token', value: Api.I.authToken);
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.restartService();
      } else {
        await FlutterForegroundTask.startService(
          serviceId: 4242,
          notificationTitle: 'AmbuRoute is watching ($name)',
          notificationText: 'You will get ambulance alerts even when the app is closed.',
          callback: bgAlertsCallback,
        );
      }
    } catch (e) {
      debugPrint('BgAlerts.start failed: $e');
    }
  }

  static Future<void> stop() async {
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }

  /// Shows the ntfy push topic for this post / hospital and opens the ntfy subscribe page.
  static Future<void> openPushSetup(BuildContext context, {required String role, required String id}) async {
    try {
      final r = await Api.I.raw('GET', '/api/push/topic', query: {'role': role, 'id': id});
      if (!context.mounted) return;
      final topic = r['topic']?.toString() ?? '';
      final url = r['subscribeUrl']?.toString() ?? '';
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Push alerts (app closed)'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('1. Install the free "ntfy" app from Play Store.\n2. Tap + and subscribe to this topic:'),
            const SizedBox(height: 8),
            SelectableText(topic, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            const Text('Now every ambulance alert rings on this phone, even if AmbuRoute is closed.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            FilledButton(
              onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
              child: const Text('OPEN'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }
}

@pragma('vm:entry-point')
void bgAlertsCallback() {
  FlutterForegroundTask.setTaskHandler(_AlertTask());
}

class _AlertTask extends TaskHandler {
  String _role = '', _id = '', _base = '', _code = '', _token = '';
  final Set<String> _seen = {};
  final FlutterTts _tts = FlutterTts();
  bool _busy = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _role = await FlutterForegroundTask.getData<String>(key: 'role') ?? '';
    _id = await FlutterForegroundTask.getData<String>(key: 'id') ?? '';
    _base = await FlutterForegroundTask.getData<String>(key: 'base') ?? '';
    _code = await FlutterForegroundTask.getData<String>(key: 'code') ?? '';
    _token = await FlutterForegroundTask.getData<String>(key: 'token') ?? '';
    try {
      await _tts.setLanguage('en-IN');
    } catch (_) {}
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _poll();
  }

  Future<void> _poll() async {
    if (_busy || _id.isEmpty || _base.isEmpty) return;
    _busy = true;
    try {
      final path = _role == 'hospital' ? '/api/hospitals/$_id/incoming' : '/api/posts/$_id/alerts';
      final res = await http.get(Uri.parse('$_base$path'), headers: {
        if (_code.isNotEmpty) 'x-access-code': _code,
        if (_token.isNotEmpty) 'x-auth-token': _token,
      }).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body);
      if (data is! Map) return;
      final list = (_role == 'hospital' ? data['ambulances'] : data['alerts']);
      if (list is! List) return;
      for (final a in list) {
        if (a is! Map) continue;
        final trip = a['tripId']?.toString() ?? '';
        final status = a['status']?.toString() ?? '';
        if (_role == 'police' && !(status == 'approaching' || status == 'imminent' || status == 'test')) continue;
        final key = '$trip|${_role == 'police' && status == 'imminent' ? 'near' : 'new'}';
        if (trip.isEmpty || _seen.contains(key)) continue;
        _seen.add(key);
        final amb = a['ambulanceId']?.toString() ?? 'Ambulance';
        final eta = a['etaSec'] is num ? ((a['etaSec'] as num) / 60).ceil() : null;
        final critical = a['priority'] == 'critical';
        String title, text;
        if (_role == 'hospital') {
          final v = a['vitals'];
          final red = v is Map && v['triage'] is Map && (v['triage'] as Map)['level'] == 'red';
          title = '${critical || red ? 'CRITICAL ' : ''}Ambulance $amb coming';
          text = 'Arrives in ${eta ?? '?'} min. Open the app and reply BED READY or NO BED.';
        } else {
          final dist = a['distAhead'] is num ? (a['distAhead'] as num).round() : null;
          title = '${critical ? 'CRITICAL ' : ''}Ambulance $amb ${status == 'imminent' ? 'very close' : 'approaching'}';
          text = '${dist ?? '?'} m away, ETA ${eta ?? '?'} min. Please clear the junction.';
        }
        await FlutterForegroundTask.updateService(notificationTitle: title, notificationText: text);
        try {
          await _tts.speak(title);
        } catch (_) {}
      }
      if (_seen.length > 300) _seen.clear();
    } catch (_) {
      // network problem: try again on the next tick
    } finally {
      _busy = false;
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }
}

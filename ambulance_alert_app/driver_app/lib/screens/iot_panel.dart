import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api.dart';
import '../models.dart';
import '../theme.dart';

/// One-tap messages for the IoT display.
class IotPreset {
  final String label;
  final String text; // shown on the display ("\n" = new line)
  final Color color;
  const IotPreset(this.label, this.text, this.color);
}

/// Control panel for an IoT device (ESP32 Super Mini with 0.96" OLED, Neo-6M GPS, buzzer, and LED light).
/// Used in both the Police app and Driver app.
class IotPanel extends StatefulWidget {
  final String title;
  final String prefsKey; // saved Device ID of the first device (see initialTarget)
  final String ambDefaultId; // default Device ID of the ambulance (driver) device
  final String policeDefaultId; // default Device ID of the police device
  final String initialTarget; // 'amb' or 'police': which device is selected first
  final String by;
  final List<IotPreset> presets;
  final bool showAuto;
  final Future<void> Function(Map<String, dynamic> cmd)? routeCommand;

  const IotPanel({
    super.key,
    required this.title,
    required this.prefsKey,
    required this.ambDefaultId,
    required this.policeDefaultId,
    this.initialTarget = 'amb',
    required this.by,
    required this.presets,
    this.showAuto = false,
    this.routeCommand,
  });

  static Future<void> show(BuildContext context, IotPanel panel) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => panel,
    );
  }

  @override
  State<IotPanel> createState() => _IotPanelState();
}

class _IotPanelState extends State<IotPanel> {
  final TextEditingController _ambCtrl = TextEditingController();
  final TextEditingController _polCtrl = TextEditingController();
  late String _target = widget.initialTarget == 'police' ? 'police' : 'amb';
  final TextEditingController _textCtrl = TextEditingController();
  final Set<String> _busy = {};
  Timer? _timer;
  IotDevice? _dev;
  String? _error;
  int _buzzSeconds = 20;
  int _displaySeconds = 120;
  bool _toRoute = false;
  bool _loaded = false;

  TextEditingController get _idCtrl => _target == 'amb' ? _ambCtrl : _polCtrl;
  String get _deviceId => _idCtrl.text.trim();

  // The old single saved ID keeps working: it belongs to the device this app controls first.
  String get _ambKey => widget.initialTarget == 'police' ? '${widget.prefsKey}_amb' : widget.prefsKey;
  String get _polKey => widget.initialTarget == 'police' ? widget.prefsKey : '${widget.prefsKey}_police';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ambCtrl.dispose();
    _polCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    String savedAmb = '';
    String savedPol = '';
    try {
      final sp = await SharedPreferences.getInstance();
      savedAmb = sp.getString(_ambKey) ?? '';
      savedPol = sp.getString(_polKey) ?? '';
    } catch (_) {}
    _ambCtrl.text = savedAmb.isNotEmpty ? savedAmb : widget.ambDefaultId;
    _polCtrl.text = savedPol.isNotEmpty ? savedPol : widget.policeDefaultId;
    if (!mounted) return;
    setState(() => _loaded = true);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  Future<void> _saveId() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_ambKey, _ambCtrl.text.trim());
      await sp.setString(_polKey, _polCtrl.text.trim());
    } catch (_) {}
  }

  bool get _idOk => RegExp(r'^[A-Za-z0-9_-]{2,40}$').hasMatch(_deviceId);

  Future<void> _refresh() async {
    if (_toRoute || !_idOk) return;
    try {
      final d = await Api.I.iot(_deviceId);
      if (mounted) setState(() { _dev = d; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _send(String key, Map<String, dynamic> cmd, String notice) async {
    setState(() => _busy.add(key));
    try {
      if (_toRoute) {
        if (widget.routeCommand == null) throw ApiException('Not running a trip.');
        await widget.routeCommand!(cmd);
      } else {
        if (!_idOk) throw ApiException('Write a valid Device ID first.');
        await _saveId();
        final updated = await Api.I.iotCommand(_deviceId, cmd, by: widget.by);
        if (mounted) setState(() => _dev = updated);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(notice)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red.shade700, content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  // Preset Message + Buzzer + LED
  void _sendPreset(IotPreset p) => _send(
        'pr_${p.label}',
        {
          'display': {'text': p.text, 'seconds': _displaySeconds},
          'buzzer': {'pattern': 'siren', 'seconds': _buzzSeconds},
          'led': {'pattern': 'strobe', 'seconds': _buzzSeconds},
        },
        'Sent "${p.label}" to display, buzzer & LED.');

  void _sendCustom() {
    final t = _textCtrl.text.trim();
    if (t.isEmpty) return;
    _send(
      'custom',
      {
        'display': {'text': t, 'seconds': _displaySeconds},
        'buzzer': {'pattern': 'beep', 'seconds': _buzzSeconds},
        'led': {'pattern': 'strobe', 'seconds': _buzzSeconds},
      },
      'Custom alert sent to IoT hardware.');
  }

  void _clearDisplay() => _send('clr_disp', {'display': null}, 'Display cleared.');

  void _buzz(String pattern, String label) => _send(
        'bz_$pattern',
        {
          'buzzer': {'pattern': pattern, 'seconds': _buzzSeconds},
          'led': {'pattern': pattern == 'off' ? 'off' : 'strobe', 'seconds': _buzzSeconds},
        },
        '$label started for $_buzzSeconds seconds.');

  void _led(String pattern, String label) => _send(
        'led_$pattern',
        {'led': {'pattern': pattern, 'seconds': _buzzSeconds}},
        '$label activated for $_buzzSeconds seconds.');

  Widget _btn(String key, IconData icon, String label, Color color, VoidCallback onTap) {
    final busy = _busy.contains(key);
    return FilledButton.icon(
      style: solidButton(color, padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14)),
      onPressed: busy ? null : onTap,
      icon: busy
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Icon(icon, size: 18),
      label: Text(label),
    );
  }

  // Realistic 0.96" OLED Display Simulation (128x64 aspect ratio)
  Widget _buildOledPreview(IotDevice? d) {
    final dispOn = d?.displayOn == true;
    final text = dispOn ? d!.displayText : 'AMBU-ROUTE SYSTEM\nReady & Standby';
    final tel = d?.telemetry;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0F1D), // Dark OLED bezel
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2B3A55), width: 3),
        boxShadow: [
          BoxShadow(color: Colors.blue.withOpacity(0.15), blurRadius: 10, spreadRadius: 1),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // OLED Top Status Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF1E88E5), // OLED active blue banner
              borderRadius: BorderRadius.circular(2),
            ),
            child: Row(
              children: [
                Text(
                  d?.id.isNotEmpty == true ? d!.id : 'DEVICE',
                  style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                ),
                const Spacer(),
                Text(
                  d?.online == true ? 'WiFi:OK' : 'WiFi:--',
                  style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                ),
                const SizedBox(width: 8),
                Text(
                  tel != null ? '${tel.sats}S' : '0S',
                  style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Main OLED Screen Area
          Container(
            height: 64,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF030712),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (dispOn) ...[
                  const Text('>> EMERGENCY ALERT <<',
                      style: TextStyle(color: Color(0xFF64B5F6), fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                  const SizedBox(height: 2),
                  Text(
                    text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFFE0F2FE), fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                  ),
                ] else ...[
                  const Text('AMBU-ROUTE IOT',
                      style: TextStyle(color: Color(0xFF64B5F6), fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                  Text(
                    tel != null && tel.fix
                        ? 'GPS: ${tel.lat?.toStringAsFixed(3)}, ${tel.lng?.toStringAsFixed(3)}'
                        : 'GPS: Searching Sats...',
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 9, fontFamily: 'monospace'),
                  ),
                  Text(
                    tel != null && tel.fix
                        ? 'Spd: ${tel.speed.round()} km/h | Sats: ${tel.sats}'
                        : 'Waiting for GPS fix...',
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 9, fontFamily: 'monospace'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCard() {
    if (_toRoute) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8)),
        child: const Text(
          'Commands go to every police post device that is on your route, ahead of you.',
          style: TextStyle(fontSize: 13),
        ),
      );
    }
    final d = _dev;
    final online = d?.online == true;
    final tel = d?.telemetry;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: online ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: online ? Colors.green.shade300 : Colors.orange.shade300),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(online ? Icons.wifi : Icons.wifi_off, size: 20, color: online ? Colors.green : Colors.deepOrange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error != null
                  ? _error!
                  : d == null
                      ? 'Checking device...'
                      : online
                          ? 'Device is online (ESP32 Super Mini)'
                          : (d.lastSeenSec == null
                              ? 'Device has never connected yet'
                              : 'Device offline (last seen ${d.lastSeenSec} s ago)'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ]),
        if (d != null) ...[
          const SizedBox(height: 8),
          if (tel != null)
            Text(
              tel.fix
                  ? 'Neo-6M GPS: ${tel.lat?.toStringAsFixed(4)}, ${tel.lng?.toStringAsFixed(4)} (${tel.sats} Sats) • ${tel.speed.round()} km/h'
                  : 'Neo-6M GPS: Searching for satellites (${tel.sats} visible)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tel.fix ? Colors.green.shade800 : Colors.orange.shade800),
            ),
          const SizedBox(height: 4),
          Text(
            '0.96" OLED: ${d.displayOn ? d.displayText.replaceAll('\n', ' / ') : 'Standby / Idle'}',
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
          Text(
            'Buzzer Siren: ${d.buzzerOn ? '${d.buzzerPattern} (${d.buzzerRemaining} s)' : 'off'} | LED Strobe: ${d.ledOn ? '${d.ledPattern} (${d.ledRemaining} s)' : 'off'}',
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final d = _dev;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: !_loaded
            ? const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const Icon(Icons.developer_board, color: BtnColors.indigo),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(widget.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                ]),
                const SizedBox(height: 12),
                if (widget.routeCommand != null) ...[
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, icon: Icon(Icons.local_hospital), label: Text('My device')),
                      ButtonSegment(value: true, icon: Icon(Icons.local_police), label: Text('Police on route')),
                    ],
                    selected: {_toRoute},
                    onSelectionChanged: (v) {
                      setState(() => _toRoute = v.first);
                      if (!_toRoute) _refresh();
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                if (!_toRoute) ...[
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'amb', icon: Icon(Icons.airport_shuttle), label: Text('Ambulance device')),
                      ButtonSegment(value: 'police', icon: Icon(Icons.local_police), label: Text('Police device')),
                    ],
                    selected: {_target},
                    onSelectionChanged: (v) {
                      setState(() {
                        _target = v.first;
                        _dev = null;
                      });
                      _refresh();
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: ValueKey(_target),
                    controller: _idCtrl,
                    decoration: InputDecoration(
                      labelText: _target == 'amb' ? 'Ambulance Device ID' : 'Police Device ID',
                      helperText: _target == 'amb'
                          ? 'Same ID configured in the ambulance ESP32 code (e.g. AMB-101)'
                          : 'Same ID configured in the police ESP32 code (e.g. POST-1)',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      errorText: _idOk ? null : 'Use 2-40 letters, numbers, - or _',
                    ),
                    onChanged: (_) => setState(() => _dev = null),
                    onSubmitted: (_) {
                      _saveId();
                      _refresh();
                    },
                  ),
                  const SizedBox(height: 10),
                ],

                // Live Status Card
                _statusCard(),
                const SizedBox(height: 12),

                // 0.96" OLED Screen Preview
                const Text('0.96" OLED DISPLAY PREVIEW', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 6),
                _buildOledPreview(d),
                const SizedBox(height: 16),

                // One-Tap Presets
                const Text('SEND ONE-TAP MESSAGE TO DISPLAY + BUZZER + LED',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in widget.presets)
                      FilledButton(
                        style: solidButton(p.color, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
                        onPressed: _busy.contains('pr_${p.label}') ? null : () => _sendPreset(p),
                        child: Text(p.label),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // Custom Message Sender
                TextField(
                  controller: _textCtrl,
                  maxLength: 64,
                  decoration: const InputDecoration(
                    labelText: 'Type custom text for 0.96" OLED display',
                    helperText: 'Will show immediately on the hardware screen',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _btn('custom', Icons.send, 'SEND TO DISPLAY & SIREN', BtnColors.indigo, _sendCustom),
                    ),
                    const SizedBox(width: 8),
                    _btn('clr_disp', Icons.clear, 'CLEAR', BtnColors.charcoal, _clearDisplay),
                  ],
                ),
                const SizedBox(height: 16),

                // Physical Actuator Controls: Siren Buzzer & LED Light
                const Text('PHYSICAL HARDWARE CONTROLS (BUZZER & LED)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: _btn('bz_siren', Icons.volume_up, 'SIREN', BtnColors.red, () => _buzz('siren', 'Siren')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _btn('bz_beep', Icons.notifications_active, 'BEEP', BtnColors.orange, () => _buzz('beep', 'Beep')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _btn('bz_off', Icons.volume_off, 'STOP AUDIO', BtnColors.charcoal, () => _buzz('off', 'Buzzer off')),
                  ),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: _btn('led_strobe', Icons.flash_on, 'LED STROBE', BtnColors.teal, () => _led('strobe', 'LED Strobe')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _btn('led_solid', Icons.lightbulb, 'LED SOLID', BtnColors.brown, () => _led('solid', 'LED Solid')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _btn('led_off', Icons.lightbulb_outline, 'LED OFF', BtnColors.charcoal, () => _led('off', 'LED off')),
                  ),
                ]),
              ]),
      ),
    );
  }
}

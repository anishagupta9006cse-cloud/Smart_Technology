import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../api.dart';
import '../models.dart';
import '../profile.dart';
import '../theme.dart';
import '../voice.dart';
import 'setup_screen.dart';

class DashboardScreen extends StatefulWidget {
  final HospitalProfile profile;
  const DashboardScreen({super.key, required this.profile});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late HospitalProfile _p;
  HospitalStatus _s = HospitalStatus();
  final TextEditingController _notes = TextEditingController();
  int _updatedAt = 0; // milliseconds, 0 = never
  bool _dirty = false;
  bool _saving = false;
  bool _loaded = false;
  String? _error;
  List<IncomingAmbulance> _incoming = [];
  final Set<String> _announced = {};
  final Set<String> _replying = {};
  Timer? _timer;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    _p = widget.profile;
    try {
      WakelockPlus.enable(); // keep the screen on so alerts are never missed
    } catch (_) {}
    _loadStatus();
    _pollIncoming();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) => _pollIncoming());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _notes.dispose();
    try {
      WakelockPlus.disable();
    } catch (_) {}
    Voice.I.stop();
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  /// If the server forgot this hospital (restart without a database), register it again.
  Future<void> _reRegister() async {
    final id = await Api.I.register(_p);
    final np = _p.withId(id);
    try {
      await np.save();
    } catch (_) {}
    if (mounted) setState(() => _p = np);
  }

  Future<void> _loadStatus() async {
    try {
      late (HospitalStatus, int) r;
      try {
        r = await Api.I.getStatus(_p.id);
      } on ApiException catch (e) {
        if (e.code != 'HOSPITAL_NOT_FOUND') rethrow;
        await _reRegister();
        r = await Api.I.getStatus(_p.id);
      }
      if (!mounted) return;
      setState(() {
        _s = r.$1;
        _updatedAt = r.$2;
        _notes.text = _s.notes;
        _loaded = true;
        _dirty = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loaded = true;
      });
    }
  }

  Future<void> _pollIncoming() async {
    if (_polling) return;
    _polling = true;
    try {
      List<IncomingAmbulance> list;
      try {
        list = await Api.I.incoming(_p.id);
      } on ApiException catch (e) {
        if (e.code != 'HOSPITAL_NOT_FOUND') rethrow;
        await _reRegister();
        list = await Api.I.incoming(_p.id);
      }
      if (!mounted) return;
      for (final a in list) {
        if (_announced.add(a.tripId)) {
          final mins = (a.etaSec / 60).ceil();
          Voice.I.speak(
              '${a.critical ? 'Critical patient. ' : ''}Ambulance ${a.ambulanceId} is coming to your hospital. It arrives in about $mins minutes.');
        }
      }
      setState(() {
        _incoming = list;
        if (_error != null && !_dirty) _error = null;
      });
    } catch (_) {
      // a short network problem is fine: the next poll will try again
    } finally {
      _polling = false;
    }
  }

  void _change(void Function() f) {
    setState(() {
      f();
      _dirty = true;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    _s.notes = _notes.text.trim();
    try {
      int at;
      try {
        at = await Api.I.updateStatus(_p.id, _s);
      } on ApiException catch (e) {
        if (e.code != 'HOSPITAL_NOT_FOUND') rethrow;
        await _reRegister();
        at = await Api.I.updateStatus(_p.id, _s);
      }
      if (!mounted) return;
      setState(() {
        _updatedAt = at;
        _dirty = false;
        _error = null;
      });
      _snack('Saved. Ambulance drivers can see this now.');
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reply(IncomingAmbulance a, String response) async {
    setState(() => _replying.add(a.tripId));
    try {
      await Api.I.respond(_p.id, a.tripId, response);
      _snack('Answer sent to ambulance ${a.ambulanceId}.');
      await _pollIncoming();
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _replying.remove(a.tripId));
    }
  }

  Future<void> _call(String phone) async {
    final number = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (number.isEmpty) return;
    try {
      final ok = await launchUrl(Uri(scheme: 'tel', path: number));
      if (!ok) _snack('Could not open the phone dialer. Number: $phone');
    } catch (_) {
      _snack('Could not open the phone dialer. Number: $phone');
    }
  }

  Future<void> _editHospital() async {
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => SetupScreen(existing: _p)));
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('This phone will stop showing ambulances for this hospital.'),
        actions: [
          TextButton(
              style: textColor(BtnColors.teal),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No')),
          FilledButton(
              style: solidButton(BtnColors.charcoal),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yes, log out')),
        ],
      ),
    );
    if (ok != true) return;
    await HospitalProfile.clear();
    if (!mounted) return;
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => const SetupScreen()));
  }

  // ------------------------------------------------------------ UI helpers
  String _ago() {
    if (_updatedAt == 0) return 'never';
    final m = ((DateTime.now().millisecondsSinceEpoch - _updatedAt) / 60000).round();
    if (m < 1) return 'just now';
    if (m < 60) return '$m min ago';
    final h = m ~/ 60;
    return h < 24 ? '$h h ago' : '${h ~/ 24} days ago';
  }

  bool get _old {
    if (_updatedAt == 0) return true;
    return DateTime.now().millisecondsSinceEpoch - _updatedAt > 2 * 3600 * 1000;
  }

  String _eta(double sec) {
    final m = (sec / 60).ceil();
    if (m <= 1) return '1 min';
    if (m < 60) return '$m min';
    return '${m ~/ 60} h ${m % 60} min';
  }

  String _dist(double m) => m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

  Widget _stepper(String label, int value, int max, void Function(int) onChanged,
      {IconData icon = Icons.bed, int step = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(icon, color: Colors.black54),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
        IconButton.filledTonal(
          onPressed: value <= 0 ? null : () => onChanged((value - step).clamp(0, max).toInt()),
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 52,
          child: Text('$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ),
        IconButton.filled(
          onPressed: value >= max ? null : () => onChanged((value + step).clamp(0, max).toInt()),
          icon: const Icon(Icons.add),
        ),
      ]),
    );
  }

  Widget _section(String title, IconData icon, Color color, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
          ]),
          const SizedBox(height: 6),
          ...children,
        ]),
      ),
    );
  }

  Widget _incomingCard(IncomingAmbulance a) {
    final color = a.critical ? Colors.red : Colors.orange;
    final busy = _replying.contains(a.tripId);
    String replied = '';
    if (a.reply == 'accepted') replied = 'You answered: BED READY';
    if (a.reply == 'no_bed') replied = 'You answered: NO BED';
    if (a.reply == 'need_info') replied = 'You answered: PLEASE CALL';
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.airport_shuttle, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Ambulance ${a.ambulanceId}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          if (a.critical)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)),
              child: const Text('CRITICAL',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11)),
            ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          _mini('ARRIVES IN', _eta(a.etaSec)),
          _mini('DISTANCE', _dist(a.remaining)),
          _mini('SPEED', '${a.speedKmh} km/h'),
        ]),
        if (a.vitals != null && a.vitals!.pulse > 0) ...[
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade300, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.monitor_heart, color: Colors.red, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          'LIVE VITALS: ${a.vitals!.emergencyType.toUpperCase()}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: a.vitals!.triageSeverity == 'red' ? Colors.red : Colors.orange,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        a.vitals!.triageSeverity.toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _vitalPill('Pulse', '${a.vitals!.pulse} bpm'),
                    const SizedBox(width: 6),
                    _vitalPill('SpO2', '${a.vitals!.spo2}%'),
                    const SizedBox(width: 6),
                    _vitalPill('BP', '${a.vitals!.bpSys}/${a.vitals!.bpDia}'),
                    const SizedBox(width: 6),
                    _vitalPill('Blood', a.vitals!.bloodGroup),
                  ],
                ),
                if (a.vitals!.notes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Paramedic Note: ${a.vitals!.notes}',
                        style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                  ),
                const SizedBox(height: 4),
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(4)),
                  child: Text(
                    'ER Prep Protocol: ${_getErPrepInstructions(a.vitals!.emergencyType)}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red.shade900),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (a.bedType.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Bed needed: ${a.bedType}', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        if (a.patientBrief.isNotEmpty) Text('Patient: ${a.patientBrief}'),
        if (a.message.isNotEmpty) Text('Driver message: ${a.message}'),
        if (a.driverName.isNotEmpty)
          Text('Driver: ${a.driverName}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
        if (replied.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(replied, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w700)),
          ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: FilledButton(
              style: solidButton(BtnColors.green),
              onPressed: busy ? null : () => _reply(a, 'accepted'),
              child: const Text('BED READY'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              style: solidButton(BtnColors.red),
              onPressed: busy ? null : () => _reply(a, 'no_bed'),
              child: const Text('NO BED'),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: FilledButton(
              style: solidButton(BtnColors.orange),
              onPressed: busy ? null : () => _reply(a, 'need_info'),
              child: const Text('PLEASE CALL'),
            ),
          ),
          if (a.contactPhone.isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                style: solidButton(BtnColors.blue),
                onPressed: () => _call(a.contactPhone),
                icon: const Icon(Icons.call),
                label: const Text('CALL'),
              ),
            ),
          ],
        ]),
      ]),
    );
  }

  Widget _mini(String label, String value) => Expanded(
        child: Column(children: [
          Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.black54)),
        ]),
      );

  Widget _vitalPill(String title, String val) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            children: [
              Text(val, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
              Text(title, style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
            ],
          ),
        ),
      );

  String _getErPrepInstructions(String type) {
    switch (type.toLowerCase()) {
      case 'cardiac':
        return 'Cath Lab on Standby • Defib ready • Cardiology fellow paged';
      case 'trauma':
        return 'Trauma OT Bay 1 ready • 2 units O-neg crossmatched • Ortho/Surgical team alerted';
      case 'stroke':
        return 'CT Scanner cleared • Stroke Code active • Neuro ICU bed assigned';
      case 'burn':
        return 'Sterile Burn Unit prepped • Parkland fluid warmup active';
      default:
        return 'Trauma triage team standing by at Bay 2';
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      appBar: AppBar(
        title: Text(_p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'edit') _editHospital();
              if (v == 'logout') _logout();
              if (v == 'refresh') {
                _loadStatus();
                _pollIncoming();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'refresh', child: Text('Refresh')),
              PopupMenuItem(value: 'edit', child: Text('Edit hospital details')),
              PopupMenuItem(value: 'logout', child: Text('Log out')),
            ],
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 100),
              children: [
                if (_error != null)
                  Container(
                    margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    padding: const EdgeInsets.all(10),
                    color: Colors.amber.shade100,
                    child: Text(_error!, style: const TextStyle(fontSize: 13)),
                  ),
                if (_old)
                  Container(
                    margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: Colors.orange.shade100, borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      _updatedAt == 0
                          ? 'You have not set your ICU and oxygen status yet. Drivers cannot trust your hospital until you do. Fill the numbers below and press UPDATE.'
                          : 'Your status is old (updated ${_ago()}). Please check the numbers and press UPDATE.',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                _section('Ambulances coming to you', Icons.emergency, Colors.red, [
                  if (_incoming.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                          'No ambulance is coming right now. This list updates by itself and you will hear a voice alert.',
                          style: TextStyle(color: Colors.black54)),
                    ),
                ]),
                ..._incoming.map(_incomingCard),
                _section('ICU beds', Icons.bed, Colors.indigo, [
                  _stepper('ICU beds FREE now', s.icuAvailable, s.icuTotal,
                      (v) => _change(() => s.icuAvailable = v)),
                  _stepper('ICU beds in total', s.icuTotal, 500, (v) {
                    _change(() {
                      s.icuTotal = v;
                      if (s.icuAvailable > v) s.icuAvailable = v;
                    });
                  }, icon: Icons.hotel),
                  _stepper('Ventilators free', s.ventilators, 500,
                      (v) => _change(() => s.ventilators = v),
                      icon: Icons.monitor_heart),
                ]),
                _section('Oxygen', Icons.air, Colors.teal, [
                  Wrap(spacing: 8, children: [
                    ChoiceChip(
                      label: const Text('Available'),
                      selected: s.oxygenLevel == 'ok',
                      selectedColor: Colors.green.shade200,
                      onSelected: (_) => _change(() => s.oxygenLevel = 'ok'),
                    ),
                    ChoiceChip(
                      label: const Text('Running LOW'),
                      selected: s.oxygenLevel == 'low',
                      selectedColor: Colors.orange.shade200,
                      onSelected: (_) => _change(() => s.oxygenLevel = 'low'),
                    ),
                    ChoiceChip(
                      label: const Text('NOT available'),
                      selected: s.oxygenLevel == 'none',
                      selectedColor: Colors.red.shade200,
                      onSelected: (_) => _change(() => s.oxygenLevel = 'none'),
                    ),
                  ]),
                  _stepper('Full oxygen cylinders', s.oxygenCylinders, 5000,
                      (v) => _change(() => s.oxygenCylinders = v),
                      icon: Icons.propane_tank, step: 1),
                ]),
                _section('Other beds and staff', Icons.medical_services, Colors.brown, [
                  _stepper('Trauma / emergency beds free', s.traumaBeds, 500,
                      (v) => _change(() => s.traumaBeds = v)),
                  _stepper('General beds free', s.generalBeds, 1000,
                      (v) => _change(() => s.generalBeds = v), icon: Icons.single_bed),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Emergency doctor on duty'),
                    value: s.emergencyDoctor,
                    onChanged: (v) => _change(() => s.emergencyDoctor = v),
                  ),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Blood available'),
                    value: s.bloodAvailable,
                    onChanged: (v) => _change(() => s.bloodAvailable = v),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _notes,
                    maxLength: 160,
                    onChanged: (_) {
                      if (!_dirty) setState(() => _dirty = true);
                    },
                    decoration: const InputDecoration(
                      labelText: 'Note for drivers (optional)',
                      hintText: 'Example: Cardiologist available till 10 PM',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ]),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text('Last updated: ${_ago()}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54, fontSize: 12)),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: FilledButton.icon(
            style: solidButton(_dirty ? BtnColors.green : BtnColors.teal,
                padding: const EdgeInsets.symmetric(vertical: 16)),
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.cloud_upload),
            label: Text(_dirty ? 'UPDATE STATUS (unsaved changes)' : 'UPDATE STATUS',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }
}

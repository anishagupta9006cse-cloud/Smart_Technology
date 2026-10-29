import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../voice.dart';

/// Result of the Smart AI screen: where to drive + what kind of emergency.
class SmartChoice {
  final PlaceResult place;
  final String emergencyType;
  final String? sosId; // set when the driver accepted a public SOS
  SmartChoice(this.place, this.emergencyType, {this.sosId});
}

const Map<String, String> kEmergencyTypes = {
  'cardiac': 'Cardiac (heart)',
  'trauma': 'Trauma / accident',
  'stroke': 'Stroke / brain',
  'burn': 'Burn',
  'maternity': 'Pregnancy',
  'pediatric': 'Child',
  'general': 'General',
};

/// SMART AI hub for the driver:
///  1. Auto BEST hospital: ETA + ICU bed + oxygen + doctor + specialty (cardiac / trauma / stroke ...)
///  2. Route type: FAST or SMOOTH (pothole-aware, for spinal / cardiac patients)
///  3. Railway gates near you (OPEN / CLOSED)
///  4. Public SOS requests near you (accept -> drive to the patient)
class SmartScreen extends StatefulWidget {
  final LatLng? near;
  final String ambulanceId;
  final String initialType;
  const SmartScreen({super.key, required this.near, required this.ambulanceId, this.initialType = 'general'});

  static Future<String> savedMode() async {
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.getString('routeMode') ?? 'fast';
    } catch (_) {
      return 'fast';
    }
  }

  @override
  State<SmartScreen> createState() => _SmartScreenState();
}

class _SmartScreenState extends State<SmartScreen> {
  late String _type;
  bool _critical = true;
  String _mode = 'fast';
  bool _busy = false;
  String? _err;
  Map<String, dynamic>? _best;
  List<Map<String, dynamic>> _ranked = [];
  List<Map<String, dynamic>> _gates = [];
  List<Map<String, dynamic>> _sos = [];

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _mode = Api.I.routeMode;
    _find();
    _loadExtras();
  }

  List<Map<String, dynamic>> _maps(dynamic l) =>
      l is List ? l.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];

  Map<String, String> get _q => {
        'lat': (widget.near?.latitude ?? 0).toString(),
        'lng': (widget.near?.longitude ?? 0).toString(),
      };

  Future<void> _find() async {
    if (widget.near == null) {
      setState(() => _err = 'Your location is not found yet. Please wait a moment and try again.');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final r = await Api.I.raw('GET', '/api/hospitals/best', query: {..._q, 'type': _type, 'critical': _critical ? '1' : '0'});
      setState(() {
        _best = r['best'] is Map ? Map<String, dynamic>.from(r['best'] as Map) : null;
        _ranked = _maps(r['ranked']);
        if (_best == null) _err = 'No hospital uses the Hospital app near you yet. Use NEAREST HOSPITAL instead.';
      });
      if (_best != null) Voice.I.speak('Best hospital: ${_best!['name']}. About ${_best!['etaMin']} minutes.');
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadExtras() async {
    if (widget.near == null) return;
    try {
      final g = await Api.I.raw('GET', '/api/railway', query: _q);
      final s = await Api.I.raw('GET', '/api/sos/open', query: _q);
      if (!mounted) return;
      setState(() {
        _gates = _maps(g['crossings']).take(8).toList();
        _sos = _maps(s['sos']);
      });
    } catch (_) {}
  }

  Future<void> _setMode(String m) async {
    setState(() => _mode = m);
    Api.I.routeMode = m;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('routeMode', m);
    } catch (_) {}
  }

  void _go(Map<String, dynamic> h) {
    final p = PlaceResult(h['name']?.toString() ?? 'Hospital',
        LatLng((h['lat'] as num).toDouble(), (h['lng'] as num).toDouble()),
        category: 'hospital', local: true);
    Navigator.pop(context, SmartChoice(p, _type));
  }

  Future<void> _acceptSos(Map<String, dynamic> s) async {
    try {
      await Api.I.raw('POST', '/api/sos/${s['id']}/accept', body: {'ambulanceId': widget.ambulanceId});
      if (!mounted) return;
      final t = s['type']?.toString() ?? 'general';
      final p = PlaceResult('SOS patient (${kEmergencyTypes[t] ?? t})',
          LatLng((s['lat'] as num).toDouble(), (s['lng'] as num).toDouble()));
      Navigator.pop(context, SmartChoice(p, t, sosId: s['id']?.toString()));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      _loadExtras();
    }
  }

  Widget _hospitalCard(Map<String, dynamic> h, {bool best = false}) {
    final warnings = (h['warnings'] is List) ? (h['warnings'] as List).map((e) => e.toString()).toList() : <String>[];
    final reasons = (h['reasons'] is List) ? (h['reasons'] as List).map((e) => e.toString()).toList() : <String>[];
    final color = warnings.isEmpty ? Colors.green : (reasons.length > warnings.length ? Colors.orange : Colors.red);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: best ? Colors.green : color, width: best ? 3 : 1)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (best)
            const Text('★ BEST HOSPITAL FOR THIS PATIENT',
                style: TextStyle(color: Colors.green, fontWeight: FontWeight.w900, fontSize: 12)),
          Row(children: [
            Expanded(child: Text(h['name']?.toString() ?? '', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
            Column(children: [
              Text('${h['etaMin']} min', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              Text('score ${h['score']}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
            ]),
          ]),
          const SizedBox(height: 4),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (final r in reasons) Chip(label: Text(r, style: const TextStyle(fontSize: 11)), backgroundColor: Colors.green.shade50, visualDensity: VisualDensity.compact),
            for (final w in warnings) Chip(label: Text(w, style: const TextStyle(fontSize: 11)), backgroundColor: Colors.red.shade50, visualDensity: VisualDensity.compact),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                style: solidButton(BtnColors.green),
                onPressed: () => _go(h),
                icon: const Icon(Icons.navigation),
                label: const Text('GO HERE'),
              ),
            ),
            if ((h['phone']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(width: 8),
              FilledButton.icon(
                style: solidButton(BtnColors.blue),
                onPressed: () => launchUrl(Uri(scheme: 'tel', path: h['phone'].toString())),
                icon: const Icon(Icons.call),
                label: const Text('CALL'),
              ),
            ],
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SMART AI: best hospital & route')),
      body: RefreshIndicator(
        onRefresh: () async {
          await _find();
          await _loadExtras();
        },
        child: ListView(padding: const EdgeInsets.all(12), children: [
          if (_sos.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.red.shade50, border: Border.all(color: Colors.red), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('🆘 PUBLIC SOS NEAR YOU', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.red)),
                for (final s in _sos)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${kEmergencyTypes[s['type']] ?? s['type']} • ${s['distance'] is num ? '${((s['distance'] as num) / 1000).toStringAsFixed(1)} km' : ''}'),
                    subtitle: Text((s['note']?.toString() ?? '').isEmpty ? 'No details' : s['note'].toString()),
                    trailing: FilledButton(style: solidButton(BtnColors.red), onPressed: () => _acceptSos(s), child: const Text('ACCEPT')),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
          ],
          const Text('1. What is the emergency?', style: TextStyle(fontWeight: FontWeight.bold)),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final e in kEmergencyTypes.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: _type == e.key,
                onSelected: (_) {
                  setState(() => _type = e.key);
                  if (e.key == 'trauma' && _mode != 'smooth') _setMode('smooth');
                  _find();
                },
              ),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Critical patient (needs ICU)'),
            value: _critical,
            onChanged: (v) {
              setState(() => _critical = v);
              _find();
            },
          ),
          const Text('2. Route type', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'fast', icon: Icon(Icons.speed), label: Text('FASTEST')),
              ButtonSegment(value: 'smooth', icon: Icon(Icons.airline_seat_flat), label: Text('SMOOTHEST')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => _setMode(s.first),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 4, bottom: 10),
            child: Text(
                'Smoothest = avoids potholes and rough roads (data from other ambulances), good for spinal injury and heart patients. Both modes avoid CLOSED railway gates and narrow lanes.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
          ),
          const Text('3. Best hospital (live ICU, oxygen, doctor, specialist)', style: TextStyle(fontWeight: FontWeight.bold)),
          if (_busy) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
          if (_err != null) Padding(padding: const EdgeInsets.all(8), child: Text(_err!, style: const TextStyle(color: Colors.red))),
          if (_best != null) _hospitalCard(_best!, best: true),
          for (final h in _ranked.skip(1)) _hospitalCard(h),
          if (_gates.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('Railway gates near you', style: TextStyle(fontWeight: FontWeight.bold)),
            for (final g in _gates)
              ListTile(
                dense: true,
                leading: Icon(Icons.train, color: g['status'] == 'closed' ? Colors.red : g['status'] == 'open' ? Colors.green : Colors.grey),
                title: Text(g['name']?.toString() ?? ''),
                trailing: Text((g['status']?.toString() ?? 'unknown').toUpperCase(),
                    style: TextStyle(fontWeight: FontWeight.bold, color: g['status'] == 'closed' ? Colors.red : Colors.black87)),
              ),
          ],
          const SizedBox(height: 30),
        ]),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import '../voice.dart';
import 'smart_screen.dart';

/// Tele-triage: the paramedic enters the patient's vitals inside the ambulance.
/// The hospital ER sees them live (app + big ER screen) and gets a CRITICAL alert if they are bad.
class VitalsScreen extends StatefulWidget {
  final String tripId;
  final String emergencyType;
  const VitalsScreen({super.key, required this.tripId, this.emergencyType = 'general'});
  @override
  State<VitalsScreen> createState() => _VitalsScreenState();
}

class _VitalsScreenState extends State<VitalsScreen> {
  final _hr = TextEditingController();
  final _spo2 = TextEditingController();
  final _sys = TextEditingController();
  final _dia = TextEditingController();
  final _rr = TextEditingController();
  final _temp = TextEditingController();
  final _sugar = TextEditingController();
  final _age = TextEditingController();
  final _complaint = TextEditingController();
  final _note = TextEditingController();
  double _gcs = 15;
  String _ecg = 'normal';
  String _gender = 'M';
  String _blood = '';
  late String _type;
  bool _busy = false;
  Map<String, dynamic>? _last;
  bool _patientSent = false;

  @override
  void initState() {
    super.initState();
    _type = widget.emergencyType;
    _load();
  }

  @override
  void dispose() {
    for (final c in [_hr, _spo2, _sys, _dia, _rr, _temp, _sugar, _age, _complaint, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Api.I.raw('GET', '/api/trips/${widget.tripId}/vitals');
      if (!mounted) return;
      setState(() => _last = r['latest'] is Map ? Map<String, dynamic>.from(r['latest'] as Map) : null);
    } catch (_) {}
  }

  num? _n(TextEditingController c) => num.tryParse(c.text.trim());

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      if (!_patientSent) {
        await Api.I.raw('POST', '/api/trips/${widget.tripId}/patient', body: {
          'emergencyType': _type,
          'age': _n(_age),
          'gender': _gender,
          'bloodGroup': _blood,
          'complaint': _complaint.text.trim(),
        });
        _patientSent = true;
      }
      final r = await Api.I.raw('POST', '/api/trips/${widget.tripId}/vitals', body: {
        'hr': _n(_hr),
        'spo2': _n(_spo2),
        'bpSys': _n(_sys),
        'bpDia': _n(_dia),
        'rr': _n(_rr),
        'temp': _n(_temp),
        'sugar': _n(_sugar),
        'gcs': _gcs.round(),
        'ecg': _ecg,
        'note': _note.text.trim(),
      });
      final v = r['vitals'] is Map ? Map<String, dynamic>.from(r['vitals'] as Map) : null;
      if (!mounted) return;
      setState(() => _last = v);
      final lvl = (v?['triage'] as Map?)?['level'];
      Voice.I.speak(lvl == 'red'
          ? 'Critical. The hospital has been alerted.'
          : 'Vitals sent to the hospital.');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sent. The hospital sees it live.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _num(String label, TextEditingController c, {String? suffix}) => Expanded(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: TextField(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: label, suffixText: suffix, border: const OutlineInputBorder(), isDense: true),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final tri = _last?['triage'] is Map ? Map<String, dynamic>.from(_last!['triage'] as Map) : null;
    final lvl = tri?['level']?.toString();
    final color = lvl == 'red' ? Colors.red : lvl == 'yellow' ? Colors.orange : Colors.green;
    return Scaffold(
      appBar: AppBar(title: const Text('Patient vitals → hospital')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        if (tri != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withAlpha(30), border: Border.all(color: color, width: 2), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('TRIAGE: ${lvl!.toUpperCase()}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: color)),
              if ((tri['flags'] as List?)?.isNotEmpty ?? false) Text((tri['flags'] as List).join(' • ')),
              const Text('The hospital sees these numbers live.', style: TextStyle(fontSize: 12, color: Colors.black54)),
            ]),
          ),
        const SizedBox(height: 10),
        const Text('Emergency type', style: TextStyle(fontWeight: FontWeight.bold)),
        Wrap(spacing: 6, children: [
          for (final e in kEmergencyTypes.entries)
            ChoiceChip(label: Text(e.value), selected: _type == e.key, onSelected: (_) => setState(() {
                  _type = e.key;
                  _patientSent = false;
                })),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _num('Age', _age),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: DropdownButtonFormField<String>(
                initialValue: _gender,
                decoration: const InputDecoration(labelText: 'Gender', border: OutlineInputBorder(), isDense: true),
                items: const [
                  DropdownMenuItem(value: 'M', child: Text('Male')),
                  DropdownMenuItem(value: 'F', child: Text('Female')),
                  DropdownMenuItem(value: 'O', child: Text('Other')),
                ],
                onChanged: (v) => setState(() {
                  _gender = v ?? 'M';
                  _patientSent = false;
                }),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: DropdownButtonFormField<String>(
                initialValue: _blood,
                decoration: const InputDecoration(labelText: 'Blood', border: OutlineInputBorder(), isDense: true),
                items: const ['', 'A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+', 'AB-']
                    .map((g) => DropdownMenuItem(value: g, child: Text(g.isEmpty ? '?' : g)))
                    .toList(),
                onChanged: (v) => setState(() {
                  _blood = v ?? '';
                  _patientSent = false;
                }),
              ),
            ),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.all(4),
          child: TextField(
            controller: _complaint,
            onChanged: (_) => _patientSent = false,
            decoration: const InputDecoration(labelText: 'Main problem (example: chest pain, accident)', border: OutlineInputBorder(), isDense: true),
          ),
        ),
        const SizedBox(height: 8),
        const Text('Vitals', style: TextStyle(fontWeight: FontWeight.bold)),
        Row(children: [_num('Heart rate', _hr, suffix: 'bpm'), _num('SpO2', _spo2, suffix: '%')]),
        Row(children: [_num('BP systolic', _sys), _num('BP diastolic', _dia)]),
        Row(children: [_num('Breathing', _rr, suffix: '/min'), _num('Temp', _temp, suffix: '°C'), _num('Sugar', _sugar)]),
        const SizedBox(height: 6),
        Text('GCS (consciousness): ${_gcs.round()}  ${_gcs <= 8 ? '— unconscious' : ''}'),
        Slider(value: _gcs, min: 3, max: 15, divisions: 12, label: _gcs.round().toString(), onChanged: (v) => setState(() => _gcs = v)),
        const Text('ECG', style: TextStyle(fontWeight: FontWeight.bold)),
        Wrap(spacing: 6, children: [
          for (final e in const {'normal': 'Normal', 'stemi': 'STEMI (heart attack)', 'afib': 'AFib', 'vt_vf': 'VT / VF', 'other': 'Other'}.entries)
            ChoiceChip(label: Text(e.value), selected: _ecg == e.key, onSelected: (_) => setState(() => _ecg = e.key)),
        ]),
        Padding(
          padding: const EdgeInsets.all(4),
          child: TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note for the doctor (optional)', border: OutlineInputBorder(), isDense: true)),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          style: solidButton(BtnColors.red, padding: const EdgeInsets.symmetric(vertical: 16)),
          onPressed: _busy ? null : _send,
          icon: const Icon(Icons.send),
          label: const Text('SEND TO HOSPITAL', style: TextStyle(fontSize: 16)),
        ),
        const SizedBox(height: 6),
        const Text('Tip: an IoT pulse-oximeter on the ESP32 can send heart rate and SpO2 automatically.',
            style: TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 30),
      ]),
    );
  }
}

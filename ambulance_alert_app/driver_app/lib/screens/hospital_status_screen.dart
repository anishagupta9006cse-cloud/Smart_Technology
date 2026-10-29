import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../models.dart';
import '../theme.dart';

/// Live list of hospitals: ICU beds, oxygen, doctor on duty.
/// The driver can pick a hospital (returns a PlaceResult) or call it.
class HospitalStatusScreen extends StatefulWidget {
  final LatLng? near;
  const HospitalStatusScreen({super.key, this.near});

  @override
  State<HospitalStatusScreen> createState() => _HospitalStatusScreenState();
}

class _HospitalStatusScreenState extends State<HospitalStatusScreen> {
  List<HospitalLive> _list = [];
  bool _loading = true;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final l = await Api.I.hospitalsLive(near: widget.near);
      if (!mounted) return;
      setState(() {
        _list = l;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _call(String phone) async {
    final number = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (number.isEmpty) return;
    try {
      final ok = await launchUrl(Uri(scheme: 'tel', path: number));
      if (!ok) _msg('Could not open the phone dialer. Number: $phone');
    } catch (_) {
      _msg('Could not open the phone dialer. Number: $phone');
    }
  }

  void _msg(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _pick(HospitalLive h) {
    Navigator.of(context).pop(
        PlaceResult(h.name, h.point, category: 'hospital', local: true, distance: h.distance));
  }

  Color _color(String ready) {
    switch (ready) {
      case 'ready':
        return const Color(0xFF2E7D32);
      case 'limited':
        return const Color(0xFFEF6C00);
      case 'not_ready':
        return const Color(0xFFC62828);
      default:
        return const Color(0xFF757575);
    }
  }

  String _label(HospitalLive h) {
    switch (h.ready) {
      case 'ready':
        return 'READY';
      case 'limited':
        return 'LIMITED';
      case 'not_ready':
        return 'NOT READY';
      default:
        return 'NO RECENT UPDATE';
    }
  }

  String _age(int? m) {
    if (m == null) return 'never updated';
    if (m < 1) return 'updated just now';
    if (m < 60) return 'updated $m min ago';
    final h = m ~/ 60;
    return h < 24 ? 'updated $h h ago' : 'updated ${h ~/ 24} days ago';
  }

  String _dist(int? d) {
    if (d == null) return '';
    return d < 1000 ? '$d m' : '${(d / 1000).toStringAsFixed(1)} km';
  }

  Widget _fact(IconData icon, String text, bool good) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Icon(icon, size: 18, color: good ? const Color(0xFF2E7D32) : const Color(0xFFC62828)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ]),
      );

  Widget _card(HospitalLive h) {
    final c = _color(h.ready);
    final oxy = !h.oxygenAvailable
        ? 'Oxygen: NOT available'
        : (h.oxygenLevel == 'low'
            ? 'Oxygen: LOW (${h.oxygenCylinders} cylinders)'
            : 'Oxygen: available (${h.oxygenCylinders} cylinders)');
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12), side: BorderSide(color: c, width: 2)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(h.name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6)),
              child: Text(_label(h),
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11)),
            ),
          ]),
          Text(
            [
              if (h.area.isNotEmpty) h.area,
              if (_dist(h.distance).isNotEmpty) _dist(h.distance),
              _age(h.ageMin),
            ].join('  •  '),
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          _fact(Icons.bed, 'ICU beds: ${h.icuAvailable} free of ${h.icuTotal}', h.icuAvailable > 0),
          _fact(Icons.air, oxy, h.oxygenAvailable && h.oxygenLevel == 'ok'),
          _fact(Icons.monitor_heart, 'Ventilators free: ${h.ventilators}', h.ventilators > 0),
          _fact(Icons.medical_services,
              h.emergencyDoctor ? 'Emergency doctor on duty' : 'NO emergency doctor now',
              h.emergencyDoctor),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
                'Trauma beds: ${h.traumaBeds}   General beds: ${h.generalBeds}   Blood: ${h.bloodAvailable ? 'yes' : 'no'}',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ),
          if (h.notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Note: ${h.notes}',
                  style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
            ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                style: solidButton(h.ready == 'not_ready' ? BtnColors.charcoal : BtnColors.green),
                onPressed: () => _pick(h),
                icon: const Icon(Icons.navigation),
                label: const Text('GO HERE'),
              ),
            ),
            if (h.phone.isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: solidButton(BtnColors.blue),
                  onPressed: () => _call(h.phone),
                  icon: const Icon(Icons.call),
                  label: const Text('CALL'),
                ),
              ),
            ],
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_loading && _list.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null && _list.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            FilledButton(
                style: solidButton(BtnColors.blue), onPressed: _load, child: const Text('TRY AGAIN')),
          ]),
        ),
      );
    } else if (_list.isEmpty) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No hospital has joined yet.\nAsk the hospital to install the AmbuRoute Hospital app and fill in its ICU and oxygen status.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(top: 6, bottom: 24),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: Text(
                'Best hospitals are shown first. Green = ICU bed free, oxygen and emergency doctor available.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
            ..._list.map(_card),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hospitals: ICU & Oxygen', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
        ],
      ),
      body: body,
    );
  }
}

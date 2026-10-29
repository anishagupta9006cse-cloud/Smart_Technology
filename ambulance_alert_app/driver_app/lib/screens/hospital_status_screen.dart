import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../voice.dart';

/// Live list of hospitals: ICU beds, oxygen, doctor on duty, specialty resources.
/// Includes 1-Tap "AUTO-PICK BEST HOSPITAL" AI matching.
class HospitalStatusScreen extends StatefulWidget {
  final LatLng? near;
  final String emergencyType;
  const HospitalStatusScreen({super.key, this.near, this.emergencyType = 'general'});

  @override
  State<HospitalStatusScreen> createState() => _HospitalStatusScreenState();
}

class _HospitalStatusScreenState extends State<HospitalStatusScreen> {
  List<HospitalLive> _list = [];
  bool _loading = true;
  String? _error;
  Timer? _timer;
  String _selectedEmergency = 'general';
  HospitalLive? _bestHospital;
  bool _aiEvaluating = false;

  @override
  void initState() {
    super.initState();
    _selectedEmergency = widget.emergencyType;
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
      _evaluateBest(silent: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _evaluateBest({bool silent = false}) async {
    if (!silent) setState(() => _aiEvaluating = true);
    try {
      final best = await Api.I.getBestHospital(
        near: widget.near,
        emergencyType: _selectedEmergency,
        routeMode: 'smooth',
      );
      if (mounted) {
        setState(() {
          _bestHospital = best;
          _aiEvaluating = false;
        });
        if (!silent && best != null) {
          Voice.I.speak('Recommended ${best.name}. ${best.matchPercentage}');
        }
      }
    } catch (_) {
      if (mounted) setState(() => _aiEvaluating = false);
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

  String _dist(int? m) {
    if (m == null) return '';
    if (m < 1000) return '$m m away';
    return '${(m / 1000).toStringAsFixed(1)} km away';
  }

  Widget _fact(IconData icon, String text, bool good) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Icon(icon, size: 18, color: good ? const Color(0xFF2E7D32) : const Color(0xFFC62828)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ]),
      );

  Widget _card(HospitalLive h, {bool isTopRecommended = false}) {
    final c = isTopRecommended ? const Color(0xFF1565C0) : _color(h.ready);
    final oxy = !h.oxygenAvailable
        ? 'Oxygen: NOT available'
        : (h.oxygenLevel == 'low'
            ? 'Oxygen: LOW (${h.oxygenCylinders} cylinders)'
            : 'Oxygen: available (${h.oxygenCylinders} cylinders)');
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      elevation: isTopRecommended ? 4 : 1,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12), side: BorderSide(color: c, width: isTopRecommended ? 2.5 : 1.5)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (isTopRecommended) ...[
            Container(
              margin: const EdgeInsets.bottom: 8,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFF1565C0), borderRadius: BorderRadius.circular(6)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, color: Colors.white, size: 14),
                  SizedBox(width: 6),
                  Text('★ AI RECOMMENDED #1 BEST HOSPITAL',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                ],
              ),
            ),
          ],
          Row(children: [
            Expanded(
              child: Text(h.name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: _color(h.ready), borderRadius: BorderRadius.circular(6)),
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
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (h.cathLab) _pill('Cath Lab (Cardiac) Ready', Colors.red),
                if (h.ctScan) _pill('CT / Neuro Ready', Colors.blue),
                if (h.traumaBeds > 0) _pill('Trauma OT Active', Colors.green),
                if (h.bloodAvailable) _pill('Blood Bank Stocked', Colors.purple),
              ],
            ),
          ),
          if (h.recommendationReason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('AI Match: ${h.recommendationReason}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF1565C0), fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 10),
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

  Widget _pill(String label, MaterialColor col) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: col.shade50, border: BorderSide(color: col.shade200), borderRadius: BorderRadius.circular(4)),
        child: Text(label, style: TextStyle(fontSize: 11, color: col.shade900, fontWeight: FontWeight.w600)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hospitals: ICU & Oxygen (Live)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _load(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Top AI Best Hospital Filter Bar
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            color: const Color(0xFFF1F5F9),
            child: Row(
              children: [
                const Icon(Icons.filter_alt, size: 20, color: Color(0xFF475569)),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _selectedEmergency,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'general', child: Text('General Emergency')),
                      DropdownMenuItem(value: 'cardiac', child: Text('❤️ Cardiac / Cath Lab')),
                      DropdownMenuItem(value: 'trauma', child: Text('💥 Severe Trauma / Bleeding')),
                      DropdownMenuItem(value: 'stroke', child: Text('🧠 Stroke / Neuro ICU')),
                      DropdownMenuItem(value: 'burn', child: Text('🔥 Burn Emergency')),
                    ],
                    onChanged: (v) {
                      setState(() => _selectedEmergency = v ?? 'general');
                      _evaluateBest();
                    },
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _aiEvaluating ? null : () => _evaluateBest(),
                  icon: _aiEvaluating ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('AUTO BEST'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
                              const SizedBox(height: 12),
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              FilledButton(onPressed: _load, child: const Text('TRY AGAIN')),
                            ],
                          ),
                        ),
                      )
                    : _list.isEmpty
                        ? const Center(child: Text('No hospitals registered yet.'))
                        : ListView.builder(
                            itemCount: _list.length,
                            itemBuilder: (context, i) {
                              final h = _list[i];
                              final isBest = _bestHospital != null && _bestHospital!.id == h.id;
                              return _card(h, isTopRecommended: isBest);
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

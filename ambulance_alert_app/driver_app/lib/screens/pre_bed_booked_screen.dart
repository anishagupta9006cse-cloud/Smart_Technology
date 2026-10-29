import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../voice.dart';

class PreBedBookedScreen extends StatefulWidget {
  final String? tripId;
  final String ambulanceId;
  final String destinationName;

  const PreBedBookedScreen({
    super.key,
    this.tripId,
    required this.ambulanceId,
    this.destinationName = '',
  });

  @override
  State<PreBedBookedScreen> createState() => _PreBedBookedScreenState();
}

class _PreBedBookedScreenState extends State<PreBedBookedScreen> {
  final _hospCtrl = TextEditingController();
  final _patientCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  String _selectedBedType = 'ICU Bed + Ventilator';
  bool _busy = false;
  BedBooking? _booking;
  List<Map<String, dynamic>> _hospitalDir = [];

  final List<String> _bedTypes = [
    'ICU Bed + Ventilator',
    'Cardiac / Cath Lab Bed',
    'Trauma OT Bed',
    'Emergency Ward Bed',
    'Pediatric ICU Bed',
  ];

  @override
  void initState() {
    super.initState();
    _hospCtrl.text = widget.destinationName.isNotEmpty ? widget.destinationName : 'Sadar Hospital Central Emergency';
    _loadDirectoryAndExisting();
  }

  @override
  void dispose() {
    _hospCtrl.dispose();
    _patientCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDirectoryAndExisting() async {
    try {
      final list = await Api.I.getHospitalsDirectory();
      if (mounted) setState(() => _hospitalDir = list);
    } catch (_) {}

    final id = widget.tripId;
    if (id != null) {
      try {
        final b = await Api.I.getBedBooking(id);
        if (b.isNotEmpty && mounted) {
          setState(() {
            _booking = BedBooking.fromJson(b);
            _hospCtrl.text = _booking!.hospitalName;
            _selectedBedType = _booking!.bedType;
            _patientCtrl.text = _booking!.patientBrief;
            _phoneCtrl.text = _booking!.contactPhone;
          });
        }
      } catch (_) {}
    }
  }

  Future<void> _confirmBooking() async {
    final hosp = _hospCtrl.text.trim();
    if (hosp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or enter the Hospital Name.')),
      );
      return;
    }

    setState(() => _busy = true);
    final booking = BedBooking(
      hospitalName: hosp,
      bedType: _selectedBedType,
      patientBrief: _patientCtrl.text.trim(),
      contactPhone: _phoneCtrl.text.trim(),
      status: 'CONFIRMED',
    );

    final tripId = widget.tripId;
    if (tripId != null) {
      try {
        await Api.I.bookBed(tripId, booking.toJson());
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _booking = booking;
      _busy = false;
    });

    Voice.I.speak('$_selectedBedType pre-booked at $hosp. Hospital reception alerted.');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.teal.shade800,
        content: Text('$_selectedBedType PRE-BOOKED at $hosp!'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pre Bed Booked', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Banner if Booked
            if (_booking != null)
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  border: Border.all(color: Colors.green.shade400, width: 2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 24),
                        const SizedBox(width: 8),
                        Text(
                          'PRE BED BOOKING CONFIRMED',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade900, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('Hospital: ${_booking!.hospitalName}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    Text('Bed Category: ${_booking!.bedType}', style: const TextStyle(fontSize: 13)),
                    if (_booking!.patientBrief.isNotEmpty)
                      Text('Patient Brief: ${_booking!.patientBrief}', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                    const SizedBox(height: 4),
                    const Text('Status: Hospital ER reception notified for immediate intake.',
                        style: TextStyle(fontSize: 11, color: Colors.black54)),
                  ],
                ),
              ),

            // Hospital Selector
            const Text('1. RECEIVING HOSPITAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            TextField(
              controller: _hospCtrl,
              decoration: const InputDecoration(
                labelText: 'Hospital Name',
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon: Icon(Icons.local_hospital, color: Colors.red),
              ),
            ),
            if (_hospitalDir.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _hospitalDir.map((h) {
                  final name = h['name']?.toString() ?? '';
                  final phone = h['emergencyPhone']?.toString() ?? '';
                  final sel = _hospCtrl.text == name;
                  return ChoiceChip(
                    label: Text(name.length > 25 ? '${name.substring(0, 25)}...' : name),
                    selected: sel,
                    onSelected: (s) {
                      if (s) {
                        setState(() {
                          _hospCtrl.text = name;
                          if (phone.isNotEmpty) _phoneCtrl.text = phone;
                        });
                      }
                    },
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 16),

            // Bed Type Selector
            const Text('2. REQUIRED BED TYPE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            for (final bt in _bedTypes)
              RadioListTile<String>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(bt, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                value: bt,
                groupValue: _selectedBedType,
                activeColor: BtnColors.indigo,
                onChanged: (v) {
                  if (v != null) setState(() => _selectedBedType = v);
                },
              ),
            const SizedBox(height: 12),

            // Patient Brief
            const Text('3. PATIENT BRIEF / COMPLAINT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            TextField(
              controller: _patientCtrl,
              maxLength: 140,
              decoration: const InputDecoration(
                hintText: 'e.g. Critical trauma patient, oxygen support on-going',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),

            // Contact Phone
            const Text('4. CONTACT NUMBER', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                hintText: 'Hospital triage desk / Doctor phone',
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon: Icon(Icons.phone, size: 20),
              ),
            ),
            const SizedBox(height: 20),

            // Confirm Button
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: BtnColors.teal,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.bookmark_added),
              label: Text(_busy ? 'CONFIRMING...' : 'CONFIRM PRE-BED BOOKING', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              onPressed: _busy ? null : _confirmBooking,
            ),
          ],
        ),
      ),
    );
  }
}

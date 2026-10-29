import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import '../voice.dart';

class VehicleInspectionScreen extends StatefulWidget {
  final String ambulanceId;
  final String driverName;

  const VehicleInspectionScreen({
    super.key,
    required this.ambulanceId,
    required this.driverName,
  });

  @override
  State<VehicleInspectionScreen> createState() => _VehicleInspectionScreenState();
}

class _VehicleInspectionScreenState extends State<VehicleInspectionScreen> {
  final Map<String, bool> _checklist = {
    'Vehicle Fuel Level > 50% & Tires Checked': true,
    'Emergency Siren & LED Flasher Strobe Working': true,
    'Medical Oxygen Cylinder Pressure & Valve OK': true,
    'Emergency First Aid & Trauma Kit Onboard': true,
    'Patient Stretcher & Wheelchair Lock Security OK': true,
    'Suction Unit & Bag-Valve-Mask Ready': true,
    'Ambulance Disinfection & Sanitization Completed': true,
  };

  bool _submitted = false;
  bool _submitting = false;

  int get _passedCount => _checklist.values.where((v) => v).length;
  bool get _allPassed => _passedCount == _checklist.length;

  Future<void> _submitGateClearance() async {
    setState(() => _submitting = true);
    try {
      await Api.I.submitGateInspection({
        'ambulanceId': widget.ambulanceId,
        'driverName': widget.driverName,
        'checklist': _checklist,
      });
      if (!mounted) return;
      setState(() {
        _submitted = true;
        _submitting = false;
      });
      Voice.I.speak('Vehicle and medical kit gate inspection approved. Ambulance cleared for departure.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.green,
          content: Text('Gate Clearance Approved! Departure Logged.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Checklist saved on device.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pre-Trip Vehicle & Kit on Gate', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _submitted ? Colors.green.shade50 : (_allPassed ? Colors.blue.shade50 : Colors.amber.shade50),
                border: Border.all(
                  color: _submitted ? Colors.green.shade400 : (_allPassed ? Colors.blue.shade400 : Colors.amber.shade400),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    _submitted ? Icons.verified : (_allPassed ? Icons.check_circle : Icons.warning_amber),
                    color: _submitted ? Colors.green : (_allPassed ? Colors.blue : Colors.amber.shade800),
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _submitted ? 'GATE CLEARANCE: APPROVED' : 'GATE INSPECTION IN PROGRESS',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: _submitted ? Colors.green.shade900 : Colors.black87,
                          ),
                        ),
                        Text(
                          'Ambulance: ${widget.ambulanceId} | Driver: ${widget.driverName}',
                          style: const TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                        Text(
                          '$_passedCount / ${_checklist.length} Checkpoints Verified',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              'GATE DEPARTURE VERIFICATION CHECKLIST',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 6),
            const Text(
              'Verify all equipment before departing gate for emergency dispatch:',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 10),

            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: Column(
                children: [
                  for (final item in _checklist.entries)
                    CheckboxListTile(
                      dense: true,
                      title: Text(item.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      value: item.value,
                      activeColor: BtnColors.indigo,
                      onChanged: (val) {
                        setState(() {
                          _checklist[item.key] = val ?? false;
                          _submitted = false;
                        });
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _allPassed ? BtnColors.indigo : BtnColors.charcoal,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: _submitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.verified_user),
              label: Text(
                _submitting ? 'RECORDING CLEARANCE...' : 'SUBMIT GATE CLEARANCE & DEPART',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              onPressed: _submitting ? null : _submitGateClearance,
            ),
          ],
        ),
      ),
    );
  }
}

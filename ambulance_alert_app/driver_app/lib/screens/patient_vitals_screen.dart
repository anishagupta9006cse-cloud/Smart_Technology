import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../voice.dart';

class PatientVitalsScreen extends StatefulWidget {
  final String tripId;
  final PatientVitals? initialVitals;
  final Function(PatientVitals)? onVitalsUpdated;

  const PatientVitalsScreen({
    super.key,
    required this.tripId,
    this.initialVitals,
    this.onVitalsUpdated,
  });

  @override
  State<PatientVitalsScreen> createState() => _PatientVitalsScreenState();
}

class _PatientVitalsScreenState extends State<PatientVitalsScreen> {
  late double _pulse;
  late double _spo2;
  late double _bpSys;
  late double _bpDia;
  late double _respRate;
  late String _bloodGroup;
  late String _emergencyType;
  late String _triageSeverity;
  late final TextEditingController _notesController;
  bool _saving = false;

  final List<String> _bloodGroups = ['O+', 'O-', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-'];

  @override
  void initState() {
    super.initState();
    final v = widget.initialVitals;
    _pulse = (v?.pulse ?? 88).toDouble();
    _spo2 = (v?.spo2 ?? 96).toDouble();
    _bpSys = (v?.bpSys ?? 125).toDouble();
    _bpDia = (v?.bpDia ?? 82).toDouble();
    _respRate = (v?.respRate ?? 18).toDouble();
    _bloodGroup = v?.bloodGroup ?? 'O+';
    _emergencyType = v?.emergencyType ?? 'cardiac';
    _triageSeverity = v?.triageSeverity ?? 'red';
    _notesController = TextEditingController(text: v?.notes ?? '');
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  PatientVitals _buildVitals() => PatientVitals(
        pulse: _pulse.round(),
        spo2: _spo2.round(),
        bpSys: _bpSys.round(),
        bpDia: _bpDia.round(),
        respRate: _respRate.round(),
        bloodGroup: _bloodGroup,
        emergencyType: _emergencyType,
        triageSeverity: _triageSeverity,
        notes: _notesController.text.trim(),
      );

  Future<void> _streamVitals() async {
    setState(() => _saving = true);
    final vitals = _buildVitals();
    try {
      await Api.I.sendVitals(widget.tripId, vitals);
      widget.onVitalsUpdated?.call(vitals);
      Voice.I.speak('Patient vitals streamed to Hospital ER');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Vitals streamed live to Hospital ER! Trauma team alerted.'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
        Navigator.of(context).pop(vitals);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error streaming vitals: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _getAiClinicalGuidance() {
    switch (_emergencyType) {
      case 'cardiac':
        return '1. Administer Aspirin 300mg chewed (unless contraindicated)\n'
            '2. High-flow Oxygen if SpO2 < 94%\n'
            '3. Continuous 12-lead ECG monitoring\n'
            '4. Defibrillator pads applied & sync standby';
      case 'trauma':
        return '1. Direct wound compression & tourniquet check\n'
            '2. Cervical spine (C-collar) immobilization\n'
            '3. Two large-bore IV lines (16-gauge)\n'
            '4. Keep patient warm to prevent trauma coagulopathy';
      case 'stroke':
        return '1. Check Blood Glucose to rule out hypoglycemia\n'
            '2. Elevate head 30 degrees\n'
            '3. Record exact time of symptom onset (FAST protocol)\n'
            '4. Nil by mouth (aspiration risk)';
      case 'burn':
        return '1. Cover with sterile dry burns dressing\n'
            '2. IV Ringers Lactate fluid resuscitation\n'
            '3. Assess airway for inhalation injury\n'
            '4. Remove constricting jewelry/clothing';
      default:
        return '1. Maintain airway, breathing, circulation\n'
            '2. Monitor vital trends every 3 minutes\n'
            '3. Keep receiving hospital updated';
    }
  }

  void _speakProtocol() {
    Voice.I.speak(_getAiClinicalGuidance());
  }

  Color _severityColor(String sev) {
    switch (sev) {
      case 'red':
        return const Color(0xFFC62828);
      case 'yellow':
        return const Color(0xFFEF6C00);
      case 'green':
        return const Color(0xFF2E7D32);
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Vitals & AI Tele-Triage'),
        backgroundColor: const Color(0xFFB71C1C),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Triage Severity Header
            Card(
              color: _severityColor(_triageSeverity).withOpacity(0.12),
              shape: RoundedRectangleBorder(
                side: BorderSide(color: _severityColor(_triageSeverity), width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'TRIAGE SEVERITY',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _severityColor(_triageSeverity),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            _triageSeverity.toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('🔴 RED (Critical)'),
                            selected: _triageSeverity == 'red',
                            onSelected: (v) => setState(() => _triageSeverity = 'red'),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('🟡 YELLOW'),
                            selected: _triageSeverity == 'yellow',
                            onSelected: (v) => setState(() => _triageSeverity = 'yellow'),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('🟢 GREEN'),
                            selected: _triageSeverity == 'green',
                            onSelected: (v) => setState(() => _triageSeverity = 'green'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 2. Emergency Type & Blood Group
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('EMERGENCY SPECIALTY CATEGORY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _emergencyType,
                      decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                      items: const [
                        DropdownMenuItem(value: 'cardiac', child: Text('❤️ Cardiac / STEMI / Heart Attack')),
                        DropdownMenuItem(value: 'trauma', child: Text('💥 Severe Trauma / Accident')),
                        DropdownMenuItem(value: 'stroke', child: Text('🧠 Stroke / Neurological')),
                        DropdownMenuItem(value: 'burn', child: Text('🔥 Severe Burn Injury')),
                        DropdownMenuItem(value: 'respiratory', child: Text('🫁 Acute Respiratory Failure')),
                        DropdownMenuItem(value: 'general', child: Text('🚑 General Medical Emergency')),
                      ],
                      onChanged: (v) => setState(() => _emergencyType = v ?? 'general'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('Blood Group: ', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 10),
                        DropdownButton<String>(
                          value: _bloodGroup,
                          items: _bloodGroups.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                          onChanged: (v) => setState(() => _bloodGroup = v ?? 'O+'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 3. Live Vital Sliders & Inputs
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('VITAL SIGNS TELEMETRY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 14),

                    // Heart Rate (Pulse)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Heart Rate (Pulse):', style: TextStyle(fontWeight: FontWeight.w600)),
                        Text('${_pulse.round()} bpm', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFFC62828))),
                      ],
                    ),
                    Slider(
                      value: _pulse,
                      min: 40,
                      max: 200,
                      divisions: 160,
                      activeColor: const Color(0xFFC62828),
                      onChanged: (v) => setState(() => _pulse = v),
                    ),

                    // SpO2
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Oxygen Saturation (SpO2):', style: TextStyle(fontWeight: FontWeight.w600)),
                        Text('${_spo2.round()} %', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _spo2 < 92 ? Colors.red : Colors.blue)),
                      ],
                    ),
                    Slider(
                      value: _spo2,
                      min: 60,
                      max: 100,
                      divisions: 40,
                      activeColor: Colors.blue,
                      onChanged: (v) => setState(() => _spo2 = v),
                    ),

                    // Blood Pressure
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Blood Pressure (Sys / Dia):', style: TextStyle(fontWeight: FontWeight.w600)),
                        Text('${_bpSys.round()} / ${_bpDia.round()} mmHg', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF2E7D32))),
                      ],
                    ),
                    Slider(
                      value: _bpSys,
                      min: 70,
                      max: 220,
                      divisions: 150,
                      activeColor: const Color(0xFF2E7D32),
                      onChanged: (v) => setState(() => _bpSys = v),
                    ),

                    // Respiration Rate
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Respiratory Rate:', style: TextStyle(fontWeight: FontWeight.w600)),
                        Text('${_respRate.round()} /min', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    Slider(
                      value: _respRate,
                      min: 8,
                      max: 45,
                      divisions: 37,
                      activeColor: Colors.purple,
                      onChanged: (v) => setState(() => _respRate = v),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 4. AI Clinical Co-Pilot Protocol
            Card(
              color: const Color(0xFFF0FDF4),
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: Color(0xFF86EFAC), width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.psychology, color: Color(0xFF166534)),
                            SizedBox(width: 8),
                            Text('AI PARAMEDIC CO-PILOT', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF166534))),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.volume_up, color: Color(0xFF166534)),
                          tooltip: 'Speak Protocol',
                          onPressed: _speakProtocol,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _getAiClinicalGuidance(),
                      style: const TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF14532D), fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 5. Paramedic Notes
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Paramedic Clinical Notes (Optional)',
                hintText: 'e.g. Sublingual nitrate administered, patient responsive...',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 18),

            // 6. Action Button
            FilledButton.icon(
              style: solidButton(BtnColors.green).copyWith(
                padding: WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 16)),
              ),
              onPressed: _saving ? null : _streamVitals,
              icon: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.cloud_upload),
              label: Text(_saving ? 'STREAMING TO ER...' : 'STREAM LIVE VITALS TO HOSPITAL ER', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }
}

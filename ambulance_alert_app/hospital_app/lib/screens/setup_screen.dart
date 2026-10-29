import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../api.dart';
import '../config.dart';
import '../location_helper.dart';
import '../profile.dart';
import '../theme.dart';
import 'dashboard_screen.dart';

class SetupScreen extends StatefulWidget {
  final HospitalProfile? existing;
  const SetupScreen({super.key, this.existing});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _area;
  late final TextEditingController _code;
  late final TextEditingController _server;
  double? _lat;
  double? _lng;
  bool _gpsBusy = false;
  bool _busy = false;
  bool _failed = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: p?.name ?? '');
    _phone = TextEditingController(text: p?.phone ?? '');
    _area = TextEditingController(text: p?.area ?? '');
    _code = TextEditingController(text: p?.accessCode ?? AppConfig.defaultAccessCode);
    _server = TextEditingController(text: p?.serverUrl ?? AppConfig.defaultServer);
    if (p != null) {
      _lat = p.lat;
      _lng = p.lng;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _area.dispose();
    _code.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _useGps() async {
    setState(() {
      _gpsBusy = true;
      _msg = null;
    });
    try {
      final err = await LocationHelper.ensureReady();
      if (err != null) {
        setState(() {
          _msg = err;
          _failed = true;
        });
        return;
      }
      Position? pos;
      try {
        pos = await Geolocator.getPositionStream(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        ).first.timeout(const Duration(seconds: 25));
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }
      final got = pos;
      if (got == null) {
        setState(() {
          _msg = 'Could not get a GPS fix. Go near a window or outdoors and try again.';
          _failed = true;
        });
        return;
      }
      setState(() {
        _lat = got.latitude;
        _lng = got.longitude;
        _failed = false;
        _msg = null;
      });
    } finally {
      if (mounted) setState(() => _gpsBusy = false);
    }
  }

  Future<void> _start() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    if (_lat == null || _lng == null) {
      setState(() {
        _failed = true;
        _msg = 'Please press "USE MY GPS" while you are at the hospital.';
      });
      return;
    }
    final url = _server.text.trim().isEmpty ? AppConfig.defaultServer : _server.text.trim();
    final code = _code.text.trim().isEmpty ? AppConfig.defaultAccessCode : _code.text.trim();
    Api.I.configure(url, code);
    setState(() {
      _busy = true;
      _failed = false;
      _msg = 'Connecting to the server...\nThe first time can take up to 1 minute. Please wait.';
    });
    final ok = await Api.I.wakeServer();
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _failed = true;
        _msg = 'Could not connect to the server. Check your internet and try again.';
      });
      return;
    }
    try {
      final draft = HospitalProfile(
        id: widget.existing?.id ?? '',
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        area: _area.text.trim(),
        lat: _lat!,
        lng: _lng!,
        accessCode: code,
        serverUrl: url,
      );
      final id = await Api.I.register(draft);
      final saved = draft.withId(id);
      try {
        await saved.save();
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => DashboardScreen(profile: saved)));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = true;
        _msg = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.local_hospital, size: 72, color: Color(0xFF00897B)),
                  const SizedBox(height: 8),
                  const Text('AMBUROUTE',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 2)),
                  const Text('Hospital',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.black54)),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                        labelText: 'Hospital name',
                        prefixIcon: Icon(Icons.local_hospital),
                        border: OutlineInputBorder()),
                    validator: (v) =>
                        (v == null || v.trim().length < 2) ? 'Please enter the hospital name' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                        labelText: 'Emergency desk phone number',
                        prefixIcon: Icon(Icons.phone),
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _area,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                        labelText: 'Area / address (optional)',
                        prefixIcon: Icon(Icons.place),
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 18),
                  const Text('Where is your hospital?', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    style: solidButton(BtnColors.teal),
                    onPressed: _gpsBusy ? null : _useGps,
                    icon: _gpsBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.my_location),
                    label: const Text('USE MY GPS (stand inside the hospital)'),
                  ),
                  if (_lat != null && _lng != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '✓ Location saved (${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)})',
                        style: const TextStyle(color: Colors.green, fontSize: 13),
                      ),
                    ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Settings (server and access code are already set)'),
                    children: [
                      TextFormField(
                        controller: _server,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                            labelText: 'Server address', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _code,
                        decoration: const InputDecoration(
                            labelText: 'Access code (already filled in)',
                            border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                  if (_msg != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(_msg!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _failed ? Colors.red : Colors.black87)),
                    ),
                  const SizedBox(height: 6),
                  FilledButton(
                    onPressed: _busy ? null : _start,
                    style: solidButton(BtnColors.green, padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: _busy
                        ? const SizedBox(
                            width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : const Text('START', style: TextStyle(fontSize: 17)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

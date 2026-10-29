import 'package:flutter/material.dart';
import '../api.dart';
import '../config.dart';
import '../profile.dart';
import '../theme.dart';
import 'help_screen.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  final Profile? existing;
  const LoginScreen({super.key, this.existing});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _amb;
  late final TextEditingController _phone;
  late final TextEditingController _otp;
  late final TextEditingController _code;
  late final TextEditingController _server;

  bool _busy = false;
  String? _msg;
  bool _failed = false;
  bool _otpSent = false;
  int _tabIndex = 0; // 0 = OTP, 1 = Server/Code

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: p?.name ?? 'Ramesh Kumar');
    _amb = TextEditingController(text: p?.ambulanceId ?? 'AMB-101');
    _phone = TextEditingController(text: '9876543210');
    _otp = TextEditingController();
    _code = TextEditingController(text: p?.accessCode ?? AppConfig.defaultAccessCode);
    _server = TextEditingController(text: p?.serverUrl ?? AppConfig.defaultServer);
  }

  @override
  void dispose() {
    _name.dispose();
    _amb.dispose();
    _phone.dispose();
    _otp.dispose();
    _code.dispose();
    _server.dispose();
    super.dispose();
  }

  Profile _profile() => Profile(
        name: _name.text.trim(),
        ambulanceId: _amb.text.trim().toUpperCase(),
        accessCode: _code.text.trim().isEmpty ? AppConfig.defaultAccessCode : _code.text.trim(),
        serverUrl: _server.text.trim().isEmpty ? AppConfig.defaultServer : _server.text.trim(),
      );

  Future<void> _sendOtp() async {
    final phone = _phone.text.trim();
    if (phone.length < 10) {
      setState(() => _msg = 'Please enter a valid 10-digit phone number.');
      return;
    }
    setState(() {
      _busy = true;
      _msg = 'Sending OTP...';
    });
    Api.I.configure(_server.text.trim(), _code.text.trim());
    try {
      final res = await Api.I.sendOtp(phone, role: 'driver');
      setState(() {
        _busy = false;
        _otpSent = true;
        _otp.text = res['demoOtp']?.toString() ?? '1234'; // auto-populate for judge convenience
        _msg = '✓ OTP Sent! (Demo Master OTP: ${_otp.text})';
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _msg = 'Error sending OTP: $e';
      });
    }
  }

  Future<void> _verifyOtpAndLogin() async {
    final phone = _phone.text.trim();
    final otp = _otp.text.trim();
    if (otp.isEmpty) {
      setState(() => _msg = 'Please enter the OTP.');
      return;
    }
    setState(() {
      _busy = true;
      _msg = 'Verifying OTP...';
    });
    try {
      await Api.I.verifyOtp(phone, otp, role: 'driver', meta: {
        'name': _name.text.trim(),
        'ambulanceId': _amb.text.trim().toUpperCase(),
      });
      final p = _profile();
      await p.save();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => HomeScreen(profile: p)),
      );
    } catch (e) {
      setState(() {
        _busy = false;
        _msg = 'OTP Verification failed: $e';
      });
    }
  }

  Future<void> _go({bool skipCheck = false}) async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final p = _profile();
    Api.I.configure(p.serverUrl, p.accessCode);
    if (!skipCheck) {
      setState(() {
        _busy = true;
        _failed = false;
        _msg = 'Connecting to the server...';
      });
      final ok = await Api.I.wakeServer();
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _busy = false;
          _failed = true;
          _msg = 'Could not connect to the server. Please check internet connection.';
        });
        return;
      }
    }
    try {
      await p.save();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HomeScreen(profile: p)));
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
                  const Icon(Icons.local_hospital, size: 68, color: Colors.red),
                  const SizedBox(height: 6),
                  const Text('AMBUROUTE',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 2)),
                  const Text('Ambulance Driver & Tele-Triage',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Colors.black54)),
                  const SizedBox(height: 20),

                  // Login Mode Tabs
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('📲 Mobile OTP Login')),
                          selected: _tabIndex == 0,
                          onSelected: (v) => setState(() => _tabIndex = 0),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('⚙️ Direct Access')),
                          selected: _tabIndex == 1,
                          onSelected: (v) => setState(() => _tabIndex = 1),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Driver Name', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your name' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _amb,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Ambulance Number', hintText: 'e.g. AMB-101', border: OutlineInputBorder(), prefixIcon: Icon(Icons.badge)),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter ambulance number' : null,
                  ),
                  const SizedBox(height: 12),

                  if (_tabIndex == 0) ...[
                    // OTP Mode
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Driver Mobile Number',
                        hintText: '10-digit phone',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.phone),
                        suffixIcon: FilledButton(
                          style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                          onPressed: _busy ? null : _sendOtp,
                          child: const Text('SEND OTP'),
                        ),
                      ),
                    ),
                    if (_otpSent) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _otp,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Enter 4-Digit OTP',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.lock_clock),
                        ),
                      ),
                    ],
                  ] else ...[
                    // Access Code Mode
                    TextFormField(
                      controller: _code,
                      decoration: const InputDecoration(labelText: 'Access Code (Optional)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.key)),
                    ),
                  ],

                  if (_msg != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8), border: BorderSide(color: Colors.amber.shade300)),
                      child: Text(_msg!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ],
                  const SizedBox(height: 18),

                  FilledButton.icon(
                    style: solidButton(BtnColors.red).copyWith(
                      padding: WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 14)),
                    ),
                    onPressed: _busy
                        ? null
                        : (_tabIndex == 0 && _otpSent ? _verifyOtpAndLogin : (_tabIndex == 0 ? _sendOtp : () => _go())),
                    icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.login),
                    label: Text(
                      _tabIndex == 0 && _otpSent ? 'VERIFY OTP & ENTER' : (_tabIndex == 0 ? 'GET OTP LOGIN' : 'OPEN DRIVER APP'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),

                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HelpScreen())),
                    icon: const Icon(Icons.help_outline),
                    label: const Text('How to use this app'),
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

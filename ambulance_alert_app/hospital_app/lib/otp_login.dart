import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';

/// Personal OTP login (each driver / officer / hospital has their own login).
/// Returns true when the login worked. The token is saved on the phone and sent with every request.
/// The shared access code keeps working as a backup, so nothing breaks if OTP is not used.
Future<bool> showOtpLogin(BuildContext context,
    {required String role, String name = '', String ambulanceId = ''}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _OtpDialog(role: role, name: name, ambulanceId: ambulanceId),
  );
  return ok == true;
}

/// Loads the saved OTP login token (call once at app start).
Future<void> loadSavedLogin() async {
  try {
    final sp = await SharedPreferences.getInstance();
    Api.I.authToken = sp.getString('authToken') ?? '';
  } catch (_) {}
}

Future<String> savedLoginPhone() async {
  try {
    final sp = await SharedPreferences.getInstance();
    return (sp.getString('authToken') ?? '').isEmpty ? '' : (sp.getString('authPhone') ?? '');
  } catch (_) {
    return '';
  }
}

Future<void> clearSavedLogin() async {
  try {
    final sp = await SharedPreferences.getInstance();
    await sp.remove('authToken');
    await sp.remove('authPhone');
  } catch (_) {}
  Api.I.authToken = '';
}

class _OtpDialog extends StatefulWidget {
  final String role;
  final String name;
  final String ambulanceId;
  const _OtpDialog({required this.role, required this.name, required this.ambulanceId});
  @override
  State<_OtpDialog> createState() => _OtpDialogState();
}

class _OtpDialogState extends State<_OtpDialog> {
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  String? _msg;
  String? _demo;

  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final r = await Api.I.raw('POST', '/api/auth/otp/request',
          body: {'phone': _phone.text.trim(), 'role': widget.role});
      setState(() {
        _sent = true;
        _demo = r['demoOtp']?.toString();
        _msg = r['mode'] == 'demo'
            ? 'Demo mode (no SMS service set on the server). Your OTP is shown below.'
            : 'OTP sent by SMS to ${_phone.text.trim()}.';
        if (_demo != null) _otp.text = _demo!;
      });
    } catch (e) {
      setState(() => _msg = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final r = await Api.I.raw('POST', '/api/auth/otp/verify', body: {
        'phone': _phone.text.trim(),
        'role': widget.role,
        'otp': _otp.text.trim(),
        'name': widget.name,
        'ambulanceId': widget.ambulanceId,
      });
      final token = r['token']?.toString() ?? '';
      if (token.isEmpty) throw Exception('Login failed. Please try again.');
      final sp = await SharedPreferences.getInstance();
      await sp.setString('authToken', token);
      await sp.setString('authPhone', _phone.text.trim());
      Api.I.authToken = token;
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _msg = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Login with OTP'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Your own login with your mobile number. Safer than one shared code.',
              style: TextStyle(fontSize: 13, color: Colors.black54)),
          const SizedBox(height: 10),
          TextField(
            controller: _phone,
            enabled: !_sent,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Mobile number', prefixText: '+91 ', border: OutlineInputBorder()),
          ),
          if (_sent) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _otp,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(labelText: '6 digit OTP', border: OutlineInputBorder()),
            ),
          ],
          if (_demo != null)
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.amber.shade100,
              child: Text('Demo OTP: $_demo', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ),
          if (_msg != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg!)),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        if (_sent)
          TextButton(onPressed: _busy ? null : () => setState(() { _sent = false; _demo = null; _otp.clear(); }), child: const Text('Change number')),
        FilledButton(
          onPressed: _busy ? null : (_sent ? _verify : _send),
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(_sent ? 'VERIFY' : 'SEND OTP'),
        ),
      ],
    );
  }
}

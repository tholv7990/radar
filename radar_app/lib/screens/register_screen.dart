import 'package:flutter/material.dart';
import '../data/repository.dart';
import '../theme.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  String? _notice;
  bool _busy = false;

  Future<void> _submit() async {
    final email = _email.text.trim();
    final pass = _pass.text;
    if (email.isEmpty || pass.isEmpty) { setState(() => _error = 'Enter an email and password.'); return; }
    if (pass.length < 6) { setState(() => _error = 'Password must be at least 6 characters.'); return; }
    if (pass != _confirm.text) { setState(() => _error = 'Passwords do not match.'); return; }
    setState(() { _busy = true; _error = null; _notice = null; });
    try {
      final signedIn = await Repository.instance.signUp(email, pass);
      if (!mounted) return;
      if (signedIn) return; // main's auth stream swaps to the app automatically
      setState(() => _notice = 'Account created. Check your email to confirm, then sign in.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not create the account. It may already exist.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() { _email.dispose(); _pass.dispose(); _confirm.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, foregroundColor: kInk),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Image.asset('assets/brand/logo_lockup.png', height: 46),
              const SizedBox(height: 8),
              const Text('Create your account', style: TextStyle(fontSize: 14, color: kMut)),
              const SizedBox(height: 20),
              TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 12),
              TextField(controller: _pass, decoration: const InputDecoration(labelText: 'Password'), obscureText: true),
              const SizedBox(height: 12),
              TextField(controller: _confirm, decoration: const InputDecoration(labelText: 'Confirm password'), obscureText: true),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: kRed))),
              if (_notice != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_notice!, style: const TextStyle(color: kGreen))),
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Creating…' : 'Create account'))),
              const SizedBox(height: 4),
              TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Already have an account?  Sign in')),
            ]),
          ),
        ),
      ),
    );
  }
}

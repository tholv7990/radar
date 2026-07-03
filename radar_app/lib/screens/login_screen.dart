import 'package:flutter/material.dart';
import '../data/repository.dart';
import '../theme.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    setState(() { _busy = true; _error = null; });
    try {
      await Repository.instance.signIn(_email.text.trim(), _pass.text);
    } catch (e) {
      setState(() => _error = 'Sign-in failed. Check your email/password.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() { _email.dispose(); _pass.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Image.asset('assets/brand/logo_lockup.png', height: 46),
              const SizedBox(height: 24),
              TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 12),
              TextField(controller: _pass, decoration: const InputDecoration(labelText: 'Password'), obscureText: true),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: kRed))),
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Signing in…' : 'Sign in'))),
              const SizedBox(height: 4),
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RegisterScreen())),
                child: const Text("Don't have an account?  Create one"),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

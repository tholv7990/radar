import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: Config.supabaseUrl, anonKey: Config.supabaseAnonKey);
  runApp(const RadarApp());
}

class RadarApp extends StatelessWidget {
  const RadarApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RADAR',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          final session = Supabase.instance.client.auth.currentSession;
          return session == null ? const _LoginPlaceholder() : const _HomePlaceholder();
        },
      ),
    );
  }
}

// Placeholders — replaced by real LoginScreen (Task 4) and HomeScaffold (Task 6).
class _LoginPlaceholder extends StatelessWidget {
  const _LoginPlaceholder();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Login')));
}

class _HomePlaceholder extends StatelessWidget {
  const _HomePlaceholder();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('RADAR — Home')));
}

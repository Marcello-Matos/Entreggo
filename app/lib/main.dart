import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api/api_client.dart';
import 'auth/auth_service.dart';
import 'config.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!AppConfig.hasSupabase) {
    runApp(const _MissingConfigApp());
    return;
  }
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabasePublishableKey,
  );
  runApp(EntreggoApp(auth: SupabaseAuthService()));
}

class EntreggoApp extends StatelessWidget {
  const EntreggoApp({super.key, required this.auth, this.api});

  final AuthService auth;
  final ApiClient? api;

  @override
  Widget build(BuildContext context) {
    final client =
        api ??
        ApiClient(
          baseUrl: AppConfig.apiBaseUrl,
          tokenProvider: () => auth.accessToken,
        );
    return MaterialApp(
      title: 'Entreggo',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: StreamBuilder<bool>(
        stream: auth.signedInChanges,
        initialData: auth.isSignedIn,
        builder: (context, snap) => snap.data == true
            ? HomeScreen(api: client, onSignOut: auth.signOut)
            : LoginScreen(auth: auth),
      ),
    );
  }
}

class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: buildTheme(),
    home: const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Configure SUPABASE_URL e SUPABASE_PUBLISHABLE_KEY via --dart-define-from-file=env.json',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'auth/auth_service.dart';
import 'config.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(EntreggoApp(auth: FirebaseAuthService()));
}

class EntreggoApp extends StatelessWidget {
  const EntreggoApp({super.key, required this.auth, this.api});

  final AuthService auth;
  final ApiClient? api;

  @override
  Widget build(BuildContext context) {
    final client =
        api ??
        ApiClient(baseUrl: AppConfig.apiBaseUrl, tokenProvider: auth.getToken);
    return MaterialApp(
      title: 'Entreggo',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: StreamBuilder<bool>(
        stream: auth.signedInChanges,
        initialData: auth.isSignedIn,
        builder: (context, snap) => snap.data == true
            ? HomeScreen(api: client, auth: auth, onSignOut: auth.signOut)
            : LoginScreen(auth: auth),
      ),
    );
  }
}

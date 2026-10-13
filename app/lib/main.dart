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
  final theme = ThemeController();
  await theme.load();
  runApp(EntreggoApp(auth: FirebaseAuthService(), theme: theme));
}

class EntreggoApp extends StatelessWidget {
  const EntreggoApp({super.key, required this.auth, this.api, this.theme});

  final AuthService auth;
  final ApiClient? api;
  final ThemeController? theme;

  @override
  Widget build(BuildContext context) {
    final client =
        api ??
        ApiClient(baseUrl: AppConfig.apiBaseUrl, tokenProvider: auth.getToken);
    final theme = this.theme ?? ThemeController();
    return ListenableBuilder(
      listenable: theme,
      builder: (context, _) => MaterialApp(
        title: 'Entreggo',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: theme.mode,
        home: StreamBuilder<bool>(
          stream: auth.signedInChanges,
          initialData: auth.isSignedIn,
          builder: (context, snap) => snap.data == true
              ? HomeScreen(
                  api: client,
                  auth: auth,
                  theme: theme,
                  onSignOut: auth.signOut,
                )
              : LoginScreen(auth: auth),
        ),
      ),
    );
  }
}

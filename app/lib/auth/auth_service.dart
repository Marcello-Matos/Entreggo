import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../firebase_options.dart';

/// Abstração do provedor de autenticação (Firebase no MVP), facilitando testes.
abstract class AuthService {
  Stream<bool> get signedInChanges;
  bool get isSignedIn;
  Future<String?> getToken();
  Future<void> signIn(String email, String password);

  /// Retorna `false` se o usuário cancelar a escolha da conta Google.
  Future<bool> signInWithGoogle();
  Future<void> signUp(String email, String password);
  Future<void> resetPassword(String email);
  Future<void> signOut();
}

class FirebaseAuthService implements AuthService {
  FirebaseAuth get _auth => FirebaseAuth.instance;

  @override
  Stream<bool> get signedInChanges =>
      _auth.authStateChanges().map((user) => user != null);

  @override
  bool get isSignedIn => _auth.currentUser != null;

  /// O SDK renova o ID token automaticamente quando está perto de expirar.
  @override
  Future<String?> getToken() async => _auth.currentUser?.getIdToken();

  @override
  Future<void> signIn(String email, String password) => _guard(
    () => _auth.signInWithEmailAndPassword(email: email, password: password),
  );

  @override
  Future<void> signUp(String email, String password) => _guard(
    () =>
        _auth.createUserWithEmailAndPassword(email: email, password: password),
  );

  @override
  Future<void> resetPassword(String email) =>
      _guard(() => _auth.sendPasswordResetEmail(email: email));

  /// Client OAuth "Web" do projeto Firebase (google-services.json, client_type 3);
  /// exigido pelo Google Sign-In no Android.
  static const _webClientId =
      '789811825272-doqormr0td0fldc95nb7iv1girsv3jgp.apps.googleusercontent.com';

  Future<void>? _googleInit;

  Future<GoogleSignIn> _google() async {
    final google = GoogleSignIn.instance;
    await (_googleInit ??= google.initialize(
      clientId: defaultTargetPlatform == TargetPlatform.iOS
          ? DefaultFirebaseOptions.ios.iosClientId
          : null,
      serverClientId: defaultTargetPlatform == TargetPlatform.android
          ? _webClientId
          : null,
    ));
    return google;
  }

  @override
  Future<bool> signInWithGoogle() async {
    final google = await _google();
    final GoogleSignInAccount account;
    try {
      account = await google.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return false;
      throw AuthFailure(
        'Não foi possível entrar com o Google (${e.code.name})',
      );
    }
    final credential = GoogleAuthProvider.credential(
      idToken: account.authentication.idToken,
    );
    await _guard(() => _auth.signInWithCredential(credential));
    return true;
  }

  @override
  Future<void> signOut() async {
    // Também encerra a sessão Google para permitir escolher outra conta depois.
    await (await _google()).signOut();
    await _auth.signOut();
  }

  Future<void> _guard(Future<Object?> Function() action) async {
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(
        _messages[e.code] ?? 'Erro de autenticação (${e.code})',
      );
    }
  }

  static const _messages = {
    'invalid-email': 'E-mail inválido',
    'invalid-credential': 'E-mail ou senha incorretos',
    'wrong-password': 'E-mail ou senha incorretos',
    'user-not-found': 'E-mail ou senha incorretos',
    'user-disabled': 'Conta desativada',
    'email-already-in-use': 'Já existe uma conta com este e-mail',
    'account-exists-with-different-credential':
        'Este e-mail já está cadastrado com outro método de login',
    'weak-password': 'Senha fraca: use pelo menos 8 caracteres',
    'too-many-requests': 'Muitas tentativas. Aguarde alguns minutos',
    'network-request-failed': 'Sem conexão com a internet',
    'operation-not-allowed':
        'Login por e-mail/senha não habilitado no Firebase',
  };
}

class AuthFailure implements Exception {
  AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

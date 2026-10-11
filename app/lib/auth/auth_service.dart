import 'package:supabase_flutter/supabase_flutter.dart';

/// Abstração do provedor de autenticação (Supabase no MVP), facilitando testes.
abstract class AuthService {
  Stream<bool> get signedInChanges;
  bool get isSignedIn;
  String? get accessToken;
  Future<void> signIn(String email, String password);
  Future<void> signUp(String email, String password);
  Future<void> resetPassword(String email);
  Future<void> signOut();
}

class SupabaseAuthService implements AuthService {
  GoTrueClient get _auth => Supabase.instance.client.auth;

  @override
  Stream<bool> get signedInChanges =>
      _auth.onAuthStateChange.map((s) => s.session != null);

  @override
  bool get isSignedIn => _auth.currentSession != null;

  @override
  String? get accessToken => _auth.currentSession?.accessToken;

  @override
  Future<void> signIn(String email, String password) =>
      _auth.signInWithPassword(email: email, password: password);

  @override
  Future<void> signUp(String email, String password) =>
      _auth.signUp(email: email, password: password);

  @override
  Future<void> resetPassword(String email) =>
      _auth.resetPasswordForEmail(email);

  @override
  Future<void> signOut() => _auth.signOut();
}

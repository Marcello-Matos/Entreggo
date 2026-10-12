import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../widgets/google_button.dart';
import '../widgets/logo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _signUp = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<Object?> Function() action, [
    String? success,
  ]) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      if (success != null) {
        messenger.showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final email = _email.text.trim();
    _signUp
        ? _run(() => widget.auth.signUp(email, _password.text), 'Conta criada!')
        : _run(() => widget.auth.signIn(email, _password.text));
  }

  void _reset() {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe seu e-mail para recuperar o acesso'),
        ),
      );
      return;
    }
    _run(
      () => widget.auth.resetPassword(email),
      'Enviamos um link de recuperação para $email',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const EntreggoLogo(markWidth: 128),
                  const SizedBox(height: 40),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'E-mail'),
                    validator: (v) => v != null && v.contains('@')
                        ? null
                        : 'Informe um e-mail válido',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(labelText: 'Senha'),
                    validator: (v) => v != null && v.length >= 8
                        ? null
                        : 'Mínimo de 8 caracteres',
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(_signUp ? 'Criar conta' : 'Entrar'),
                  ),
                  const OrDivider(),
                  GoogleSignInButton(
                    onPressed: _busy
                        ? null
                        : () => _run(widget.auth.signInWithGoogle),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _signUp = !_signUp),
                    child: Text(_signUp ? 'Já tenho conta' : 'Criar uma conta'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _reset,
                    child: const Text('Esqueci minha senha'),
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

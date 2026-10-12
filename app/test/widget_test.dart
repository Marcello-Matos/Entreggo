import 'dart:async';
import 'dart:convert';

import 'package:entreggo/api/api_client.dart';
import 'package:entreggo/api/models.dart';
import 'package:entreggo/auth/auth_service.dart';
import 'package:entreggo/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeAuth implements AuthService {
  FakeAuth({this.signedIn = false});

  final _changes = StreamController<bool>.broadcast();
  bool signedIn;
  String? lastEmail;

  @override
  Stream<bool> get signedInChanges => _changes.stream;
  @override
  bool get isSignedIn => signedIn;
  @override
  Future<String?> getToken() async => signedIn ? 'token' : null;
  @override
  Future<void> signIn(String email, String password) async {
    lastEmail = email;
    signedIn = true;
    _changes.add(true);
  }

  @override
  Future<bool> signInWithGoogle() async {
    lastEmail = 'google';
    signedIn = true;
    _changes.add(true);
    return true;
  }

  @override
  Future<void> signUp(String email, String password) async {}
  @override
  Future<void> resetPassword(String email) async {}
  @override
  Future<void> signOut() async {
    signedIn = false;
    _changes.add(false);
  }
}

ApiClient fakeApi(List<Map<String, dynamic>> routes) => ApiClient(
  baseUrl: 'http://api.test',
  tokenProvider: () async => 'token',
  httpClient: MockClient((req) async {
    expect(req.headers['Authorization'], 'Bearer token');
    return http.Response.bytes(
      utf8.encode(jsonEncode(routes)),
      200,
      headers: {'content-type': 'application/json'},
    );
  }),
);

void main() {
  testWidgets('login valida campos antes de enviar', (tester) async {
    final auth = FakeAuth();
    await tester.pumpWidget(EntreggoApp(auth: auth, api: fakeApi([])));

    expect(find.text('Sua rota. Otimizada.'), findsOneWidget);
    await tester.tap(find.text('Entrar'));
    await tester.pump();
    expect(find.text('Informe um e-mail válido'), findsOneWidget);
    expect(auth.lastEmail, isNull);
  });

  testWidgets('após login mostra as rotas do usuário', (tester) async {
    final auth = FakeAuth();
    final api = fakeApi([
      {'id': 'r1', 'title': 'Centro', 'status': 'optimized'},
    ]);
    await tester.pumpWidget(EntreggoApp(auth: auth, api: api));

    await tester.enterText(find.byType(TextFormField).at(0), 'a@entreggo.app');
    await tester.enterText(find.byType(TextFormField).at(1), 'senha-segura');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    expect(find.text('Iniciar entregas de hoje'), findsOneWidget);
    expect(find.text('Centro'), findsOneWidget);
    expect(find.text('Otimizada'), findsOneWidget);
  });

  testWidgets('botão do Google faz login', (tester) async {
    final auth = FakeAuth();
    await tester.pumpWidget(EntreggoApp(auth: auth, api: fakeApi([])));

    await tester.tap(find.text('Continuar com o Google'));
    await tester.pumpAndSettle();

    expect(auth.lastEmail, 'google');
    expect(find.text('Iniciar entregas de hoje'), findsOneWidget);
  });

  test('RouteDetail ordena pacotes pela sequência sugerida', () {
    final detail = RouteDetail.fromJson({
      'id': 'r1',
      'title': 'Rota',
      'status': 'optimized',
      'packages': [
        for (final id in ['a', 'b', 'c'])
          {'id': id, 'status': 'pending', 'address_status': 'ready'},
      ],
      'stops': [
        {'package_id': 'c', 'sequence': 1},
        {'package_id': 'a', 'sequence': 2},
      ],
      'optimization': null,
    });
    expect(detail.orderedPackages.map((p) => p.id), ['c', 'a', 'b']);
  });

  test('ApiClient converte erro 409 em duplicidade', () async {
    final api = ApiClient(
      baseUrl: 'http://api.test',
      tokenProvider: () async => 'token',
      httpClient: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(
            jsonEncode({'detail': 'Código já cadastrado nesta rota'}),
          ),
          409,
        ),
      ),
    );
    expect(
      () => api.scan('r1', 'X'),
      throwsA(isA<ApiException>().having((e) => e.isDuplicate, 'dup', true)),
    );
  });
}

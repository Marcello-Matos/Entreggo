import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  bool get isDuplicate => statusCode == 409;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this.tokenProvider,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final Future<String?> Function() tokenProvider;
  final http.Client _http;

  Future<dynamic> _send(String method, String path, {Object? body}) async {
    final token = await tokenProvider();
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers['Content-Type'] = 'application/json'
      ..headers['Authorization'] = 'Bearer ${token ?? ''}';
    if (body != null) request.body = jsonEncode(body);
    return _decode(request);
  }

  Future<dynamic> _decode(http.BaseRequest request) async {
    final response = await http.Response.fromStream(await _http.send(request));
    Object? decoded;
    try {
      decoded = response.bodyBytes.isEmpty
          ? null
          : jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      if (response.statusCode < 400) rethrow;
    }
    if (response.statusCode >= 400) {
      final detail = decoded is Map ? decoded['detail'] : null;
      throw ApiException(
        response.statusCode,
        detail is String ? detail : 'Erro ${response.statusCode}',
      );
    }
    return decoded;
  }

  /// Resumo desde a meia-noite local do aparelho.
  Future<Dashboard> dashboard() async {
    final now = DateTime.now();
    final since = DateTime(now.year, now.month, now.day).toUtc();
    return Dashboard.fromJson(
      await _send(
        'GET',
        '/v1/dashboard?since=${Uri.encodeQueryComponent(since.toIso8601String())}',
      ) as Map<String, dynamic>,
    );
  }

  /// Estado da assinatura (trial, Play ou gratuito).
  Future<Subscription> subscription() async => Subscription.fromJson(
    await _send('GET', '/v1/subscription') as Map<String, dynamic>,
  );

  /// Registra o purchase token do Google Play e libera o Pro.
  Future<Subscription> registerPlayPurchase(
    String productId,
    String purchaseToken,
  ) async => Subscription.fromJson(
    await _send(
      'POST',
      '/v1/subscription/play',
      body: {'product_id': productId, 'purchase_token': purchaseToken},
    ) as Map<String, dynamic>,
  );

  Future<List<DeliveryRoute>> listRoutes() async => [
    for (final r in await _send('GET', '/v1/routes') as List)
      DeliveryRoute.fromJson(r as Map<String, dynamic>),
  ];

  Future<DeliveryRoute> createRoute(
    String title, {
    String? startAddress,
  }) async => DeliveryRoute.fromJson(
    await _send(
      'POST',
      '/v1/routes',
      body: {'title': title, 'start_address': startAddress},
    ),
  );

  Future<RouteDetail> getRoute(String id) async =>
      RouteDetail.fromJson(await _send('GET', '/v1/routes/$id'));

  Future<DeliveryRoute> renameRoute(String id, String title) async =>
      DeliveryRoute.fromJson(
        await _send('PATCH', '/v1/routes/$id', body: {'title': title}),
      );

  Future<void> deleteRoute(String id) => _send('DELETE', '/v1/routes/$id');

  Future<Package> scan(String routeId, String code) async => Package.fromJson(
    await _send('POST', '/v1/routes/$routeId/scan', body: {'code': code}),
  );

  Future<Package> addPackage(
    String routeId, {
    String? trackingCode,
    AddressInput? address,
  }) async => Package.fromJson(
    await _send(
      'POST',
      '/v1/routes/$routeId/packages',
      body: {'tracking_code': trackingCode, ...?address?.toJson()},
    ),
  );

  Future<Map<String, dynamic>> geocode(String routeId) async =>
      await _send('POST', '/v1/routes/$routeId/geocode')
          as Map<String, dynamic>;

  /// Partida: coordenadas do GPS ou, na falta delas, um endereço digitado.
  Future<Map<String, dynamic>> optimize(
    String routeId, {
    double? startLat,
    double? startLng,
    String? startAddress,
  }) async => await _send(
    'POST',
    '/v1/routes/$routeId/optimize',
    body: {
      'start_lat': startLat,
      'start_lng': startLng,
      'start_address': startAddress,
    },
  ) as Map<String, dynamic>;

  Future<void> updateAddress(String packageId, AddressInput address) =>
      _send('PATCH', '/v1/packages/$packageId', body: address.toJson());

  /// Envia planilha CSV/XLSX; retorna o resumo da importação.
  Future<Map<String, dynamic>> importFile(
    String routeId,
    String filename,
    List<int> bytes,
  ) async {
    final token = await tokenProvider();
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/v1/import-jobs'))
          ..headers['Authorization'] = 'Bearer ${token ?? ''}'
          ..fields['route_id'] = routeId
          ..files.add(
            http.MultipartFile.fromBytes('file', bytes, filename: filename),
          );
    final job = await _decode(request) as Map<String, dynamic>;
    final summary = (job['error_summary'] as Map<String, dynamic>?) ?? {};
    if (job['status'] == 'failed') {
      throw ApiException(
        422,
        summary['message'] as String? ?? 'Falha na importação',
      );
    }
    return summary;
  }

  /// Atualiza o status; `note` guarda o motivo padronizado da falha e
  /// `recipientName`/`lat`/`lng` compõem o comprovante de entrega.
  Future<void> updateStatus(
    String packageId,
    String status, {
    String? note,
    String? recipientName,
    String? deliveryMethod,
    double? lat,
    double? lng,
  }) => _send(
    'PATCH',
    '/v1/packages/$packageId/status',
    body: {
      'status': status,
      'note': note,
      'recipient_name': recipientName,
      'delivery_method': deliveryMethod,
      'lat': lat,
      'lng': lng,
    },
  );

  /// Plano de carga: grava o local no veículo de vários pacotes de uma vez.
  /// `assignments`: {package_id: local}.
  Future<void> setLocations(String routeId, Map<String, String> assignments) =>
      _send(
        'POST',
        '/v1/routes/$routeId/locations',
        body: {
          'assignments': [
            for (final e in assignments.entries)
              {'package_id': e.key, 'location': e.value},
          ],
        },
      );

  /// Posição do pacote no veículo (`null` remove o local).
  Future<void> updateLocation(String packageId, String? location) => _send(
    'PATCH',
    '/v1/packages/$packageId/location',
    body: {'location': location},
  );

  /// Foto do pacote no local (comprovante de entrega/tentativa).
  Future<void> uploadDeliveryPhoto(
    String packageId,
    List<int> bytes, {
    String filename = 'entrega.jpg',
  }) async {
    final token = await tokenProvider();
    final request =
        http.MultipartRequest(
            'PUT',
            Uri.parse('$baseUrl/v1/packages/$packageId/photo'),
          )
          ..headers['Authorization'] = 'Bearer ${token ?? ''}'
          ..files.add(
            http.MultipartFile.fromBytes('file', bytes, filename: filename),
          );
    await _decode(request);
  }

  Future<void> deletePackage(String packageId) =>
      _send('DELETE', '/v1/packages/$packageId');

  /// Envia a foto de perfil (JPEG/PNG/HEIC/WebP/GIF/BMP, até 5 MB).
  Future<void> uploadPhoto(
    List<int> bytes, {
    String filename = 'foto.jpg',
  }) async {
    final token = await tokenProvider();
    final request =
        http.MultipartRequest('PUT', Uri.parse('$baseUrl/v1/users/me/photo'))
          ..headers['Authorization'] = 'Bearer ${token ?? ''}'
          ..files.add(
            http.MultipartFile.fromBytes('file', bytes, filename: filename),
          );
    await _decode(request);
  }

  /// Foto de perfil enviada pelo usuário; `null` se não houver.
  Future<Uint8List?> fetchPhoto() async {
    final token = await tokenProvider();
    final request = http.Request('GET', Uri.parse('$baseUrl/v1/users/me/photo'))
      ..headers['Authorization'] = 'Bearer ${token ?? ''}';
    final response = await http.Response.fromStream(await _http.send(request));
    if (response.statusCode == 404) return null;
    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, 'Erro ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  Future<void> deletePhoto() => _send('DELETE', '/v1/users/me/photo');
}

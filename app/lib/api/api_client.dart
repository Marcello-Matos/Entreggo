import 'dart:convert';

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
  final String? Function() tokenProvider;
  final http.Client _http;

  Future<dynamic> _send(String method, String path, {Object? body}) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers['Content-Type'] = 'application/json'
      ..headers['Authorization'] = 'Bearer ${tokenProvider() ?? ''}';
    if (body != null) request.body = jsonEncode(body);
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

  Future<List<DeliveryRoute>> listRoutes() async => [
    for (final r in await _send('GET', '/v1/routes') as List)
      DeliveryRoute.fromJson(r as Map<String, dynamic>),
  ];

  Future<DeliveryRoute> createRoute(
    String title, {
    double? startLat,
    double? startLng,
  }) async => DeliveryRoute.fromJson(
    await _send(
      'POST',
      '/v1/routes',
      body: {'title': title, 'start_lat': startLat, 'start_lng': startLng},
    ),
  );

  Future<RouteDetail> getRoute(String id) async =>
      RouteDetail.fromJson(await _send('GET', '/v1/routes/$id'));

  Future<Package> scan(String routeId, String code) async => Package.fromJson(
    await _send('POST', '/v1/routes/$routeId/scan', body: {'code': code}),
  );

  Future<Package> addPackage(
    String routeId, {
    String? trackingCode,
    String? address,
    String? city,
  }) async => Package.fromJson(
    await _send(
      'POST',
      '/v1/routes/$routeId/packages',
      body: {
        'tracking_code': trackingCode,
        'address_text': address,
        'city': city,
      },
    ),
  );

  Future<Map<String, dynamic>> geocode(String routeId) async =>
      await _send('POST', '/v1/routes/$routeId/geocode')
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> optimize(String routeId) async =>
      await _send('POST', '/v1/routes/$routeId/optimize')
          as Map<String, dynamic>;

  Future<void> updateStatus(String packageId, String status) => _send(
    'PATCH',
    '/v1/packages/$packageId/status',
    body: {'status': status},
  );
}

class DeliveryRoute {
  DeliveryRoute({
    required this.id,
    required this.title,
    required this.status,
    this.startLat,
    this.startLng,
  });

  factory DeliveryRoute.fromJson(Map<String, dynamic> j) => DeliveryRoute(
    id: j['id'] as String,
    title: j['title'] as String,
    status: j['status'] as String,
    startLat: (j['start_lat'] as num?)?.toDouble(),
    startLng: (j['start_lng'] as num?)?.toDouble(),
  );

  final String id;
  final String title;
  final String status;
  final double? startLat;
  final double? startLng;
}

class Package {
  Package({
    required this.id,
    required this.status,
    required this.addressStatus,
    this.trackingCode,
    this.addressText,
    this.city,
  });

  factory Package.fromJson(Map<String, dynamic> j) => Package(
    id: j['id'] as String,
    status: j['status'] as String,
    addressStatus: j['address_status'] as String,
    trackingCode: j['tracking_code'] as String?,
    addressText: j['address_text'] as String?,
    city: j['city'] as String?,
  );

  final String id;
  final String status;
  final String addressStatus;
  final String? trackingCode;
  final String? addressText;
  final String? city;
}

class RouteDetail {
  RouteDetail({
    required this.route,
    required this.packages,
    required this.sequence,
    this.optimization,
  });

  factory RouteDetail.fromJson(Map<String, dynamic> j) => RouteDetail(
    route: DeliveryRoute.fromJson(j),
    packages: [
      for (final p in j['packages'] as List)
        Package.fromJson(p as Map<String, dynamic>),
    ],
    sequence: {
      for (final s in j['stops'] as List)
        (s as Map<String, dynamic>)['package_id'] as String:
            s['sequence'] as int,
    },
    optimization: j['optimization'] as Map<String, dynamic>?,
  );

  final DeliveryRoute route;
  final List<Package> packages;

  /// package_id -> posição na ordem sugerida.
  final Map<String, int> sequence;
  final Map<String, dynamic>? optimization;

  /// Pacotes otimizados primeiro, na ordem sugerida; os demais ao final.
  List<Package> get orderedPackages {
    final list = [...packages];
    list.sort(
      (a, b) =>
          (sequence[a.id] ?? 1 << 30).compareTo(sequence[b.id] ?? 1 << 30),
    );
    return list;
  }
}

class DeliveryRoute {
  DeliveryRoute({
    required this.id,
    required this.title,
    required this.status,
    required this.createdAt,
    this.startAddress,
    this.startLat,
    this.startLng,
  });

  factory DeliveryRoute.fromJson(Map<String, dynamic> j) => DeliveryRoute(
    id: j['id'] as String,
    title: j['title'] as String,
    status: j['status'] as String,
    createdAt:
        DateTime.tryParse(j['created_at'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
    startAddress: j['start_address'] as String?,
    startLat: (j['start_lat'] as num?)?.toDouble(),
    startLng: (j['start_lng'] as num?)?.toDouble(),
  );

  final String id;
  final String title;
  final String status;
  final DateTime createdAt;
  final String? startAddress;
  final double? startLat;
  final double? startLng;

  bool get isFinished => status == 'completed' || status == 'archived';
}

/// Dados de endereço enviados ao criar/corrigir um pacote.
class AddressInput {
  const AddressInput({
    required this.address,
    this.city,
    this.state,
    this.postalCode,
    this.notes,
  });

  final String address;
  final String? city;
  final String? state;
  final String? postalCode;
  final String? notes;

  Map<String, dynamic> toJson() => {
    'address_text': address,
    'city': city,
    'state': state,
    'postal_code': postalCode,
    'delivery_notes': notes,
  };
}

class Package {
  Package({
    required this.id,
    required this.status,
    required this.addressStatus,
    this.trackingCode,
    this.addressText,
    this.city,
    this.state,
    this.postalCode,
    this.deliveryNotes,
    this.lat,
    this.lng,
  });

  factory Package.fromJson(Map<String, dynamic> j) => Package(
    id: j['id'] as String,
    status: j['status'] as String,
    addressStatus: j['address_status'] as String,
    trackingCode: j['tracking_code'] as String?,
    addressText: j['address_text'] as String?,
    city: j['city'] as String?,
    state: j['state'] as String?,
    postalCode: j['postal_code'] as String?,
    deliveryNotes: j['delivery_notes'] as String?,
    lat: (j['lat'] as num?)?.toDouble(),
    lng: (j['lng'] as num?)?.toDouble(),
  );

  final String id;
  final String status;
  final String addressStatus;
  final String? trackingCode;
  final String? addressText;
  final String? city;
  final String? state;
  final String? postalCode;
  final String? deliveryNotes;
  final double? lat;
  final double? lng;

  bool get hasCoordinates => lat != null && lng != null;

  /// "Rua X, 120 — São Paulo/SP"
  String get displayAddress => [
    addressText ?? 'Sem endereço',
    if (city != null) state != null ? '$city/$state' : city!,
  ].join(' — ');
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

  /// Paradas da rota otimizada, na ordem de entrega.
  List<Package> get stops =>
      orderedPackages.where((p) => sequence.containsKey(p.id)).toList();

  bool get isOptimized =>
      optimization != null &&
      sequence.isNotEmpty &&
      (route.status == 'optimized' ||
          route.status == 'in_progress' ||
          route.status == 'completed');

  int get missingAddress =>
      packages.where((p) => p.addressStatus != 'ready').length;
}

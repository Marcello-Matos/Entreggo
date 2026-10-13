class DeliveryRoute {
  DeliveryRoute({
    required this.id,
    required this.title,
    required this.status,
    required this.createdAt,
    this.startAddress,
    this.startLat,
    this.startLng,
    this.totalPackages = 0,
    this.deliveredPackages = 0,
    this.pendingPackages = 0,
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
    totalPackages: j['total_packages'] as int? ?? 0,
    deliveredPackages: j['delivered_packages'] as int? ?? 0,
    pendingPackages: j['pending_packages'] as int? ?? 0,
  );

  final String id;
  final String title;
  final String status;
  final DateTime createdAt;
  final String? startAddress;
  final double? startLat;
  final double? startLng;
  final int totalPackages;
  final int deliveredPackages;
  final int pendingPackages;

  bool get isFinished => status == 'completed' || status == 'archived';
}

/// Resumo do dia exibido na tela inicial.
class Dashboard {
  const Dashboard({
    this.packages = 0,
    this.delivered = 0,
    this.failed = 0,
    this.skipped = 0,
    this.pending = 0,
    this.progress = 0,
    this.activeRouteId,
    this.activeRouteTitle,
    this.activeRemaining = 0,
    this.activeOptimized = false,
  });

  factory Dashboard.fromJson(Map<String, dynamic> j) {
    final active = j['active_route'] as Map<String, dynamic>?;
    return Dashboard(
      packages: j['packages'] as int,
      delivered: j['delivered'] as int,
      failed: j['failed'] as int,
      skipped: j['skipped'] as int,
      pending: j['pending'] as int,
      progress: (j['progress'] as num).toDouble(),
      activeRouteId: active?['id'] as String?,
      activeRouteTitle: active?['title'] as String?,
      activeRemaining: active?['remaining'] as int? ?? 0,
      activeOptimized: active?['optimized'] as bool? ?? false,
    );
  }

  final int packages;
  final int delivered;
  final int failed;
  final int skipped;
  final int pending;
  final double progress;
  final String? activeRouteId;
  final String? activeRouteTitle;
  final int activeRemaining;
  final bool activeOptimized;
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

  /// Mutável: a tela de entrega atualiza o status localmente após o PATCH,
  /// sem recarregar a rota inteira do servidor.
  String status;
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

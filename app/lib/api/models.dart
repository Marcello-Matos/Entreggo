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
    this.nextAddress,
    this.nextLat,
    this.nextLng,
    this.remainingSeconds,
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
      nextAddress: active?['next_address'] as String?,
      nextLat: (active?['next_lat'] as num?)?.toDouble(),
      nextLng: (active?['next_lng'] as num?)?.toDouble(),
      remainingSeconds: active?['remaining_seconds'] as int?,
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

  /// Próxima parada da rota ativa e tempo estimado para concluir o restante.
  final String? nextAddress;
  final double? nextLat;
  final double? nextLng;
  final int? remainingSeconds;

  String get remainingLabel {
    final s = remainingSeconds;
    if (s == null) return '';
    final m = (s / 60).round();
    return m < 60
        ? '$m min'
        : '${m ~/ 60}h${(m % 60).toString().padLeft(2, '0')}';
  }
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
    this.recipientName,
    this.deliveryMethod,
    this.deliveredAt,
    this.hasProofPhoto = false,
    this.vehicleLocation,
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
    recipientName: j['recipient_name'] as String?,
    deliveryMethod: j['delivery_method'] as String?,
    deliveredAt: DateTime.tryParse(j['delivered_at'] as String? ?? '')
        ?.toLocal(),
    hasProofPhoto: j['has_proof_photo'] as bool? ?? false,
    vehicleLocation: j['vehicle_location'] as String?,
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

  /// Comprovante: quem recebeu, como e quando (registrado pelo servidor).
  final String? recipientName;
  final String? deliveryMethod;
  final DateTime? deliveredAt;
  final bool hasProofPhoto;

  /// Posição física no veículo ("Fundo • Meio • Prateleira").
  /// Mutável: o app atualiza localmente após o PATCH de local.
  String? vehicleLocation;

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
    required this.etas,
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
    etas: {
      for (final s in j['stops'] as List)
        (s as Map<String, dynamic>)['package_id'] as String: DateTime.tryParse(
          s['eta_estimate'] as String? ?? '',
        )?.toLocal(),
    },
    optimization: j['optimization'] as Map<String, dynamic>?,
  );

  final DeliveryRoute route;
  final List<Package> packages;
  final Map<String, DateTime?> etas;

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

  /// Primeira parada ainda pendente — a "próxima entrega".
  Package? get nextStop =>
      stops.where((p) => p.status == 'pending').firstOrNull;

  /// Tempo estimado para concluir as paradas restantes (da próxima até a última).
  int? get remainingSeconds {
    final next = nextStop;
    if (next == null) return null;
    final firstEta = etas[next.id];
    final all = etas.values.whereType<DateTime>();
    if (firstEta == null || all.isEmpty) return null;
    final lastEta = all.reduce((a, b) => a.isAfter(b) ? a : b);
    final s = lastEta.difference(firstEta).inSeconds;
    return s < 0 ? 0 : s;
  }

  bool get isOptimized =>
      optimization != null &&
      sequence.isNotEmpty &&
      (route.status == 'optimized' ||
          route.status == 'in_progress' ||
          route.status == 'completed');

  int get missingAddress =>
      packages.where((p) => p.addressStatus != 'ready').length;
}

/// Assinatura do usuário (trial, Google Play ou plano gratuito).
class Subscription {
  const Subscription({
    required this.entitlement,
    required this.source,
    this.productId,
    this.expiresAt,
    this.limits = const {},
  });

  factory Subscription.fromJson(Map<String, dynamic> j) => Subscription(
    entitlement: j['entitlement'] as String,
    source: j['source'] as String? ?? 'default',
    productId: j['product_id'] as String?,
    expiresAt: j['expires_at'] != null
        ? DateTime.tryParse(j['expires_at'] as String)
        : null,
    limits: {
      for (final e in (j['limits'] as Map?)?.entries ?? const Iterable.empty())
        e.key.toString(): (e.value as num).toInt(),
    },
  );

  final String entitlement; // free | pro | team
  final String source; // trial | play | default
  final String? productId;
  final DateTime? expiresAt;
  final Map<String, int> limits;

  bool get isPro => entitlement != 'free';
  bool get isTrial => source == 'trial' && isPro;
  bool get trialExpired => source == 'trial' && !isPro;

  /// Dias restantes do trial (0 quando expirado).
  int get trialDaysLeft {
    final exp = expiresAt;
    if (exp == null) return 0;
    final d = exp.difference(DateTime.now()).inDays;
    return d < 0 ? 0 : d;
  }
}

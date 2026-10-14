import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../routing/location.dart';
import '../theme.dart';
import '../widgets/status.dart';
import 'delivery_screen.dart';

/// Mapa da rota otimizada: paradas numeradas na ordem de entrega e o botão
/// para iniciar a navegação (Google Maps/Waze parada a parada).
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.api, required this.routeId});

  final ApiClient api;
  final String routeId;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late Future<RouteDetail> _detail = widget.api.getRoute(widget.routeId);
  LatLng? _me;

  @override
  void initState() {
    super.initState();
    // Posição atual do motorista, marcada no mapa quando disponível.
    currentPosition().then((pos) {
      if (pos != null && mounted) {
        setState(() => _me = LatLng(pos.latitude, pos.longitude));
      }
    });
  }

  void _reload() =>
      setState(() => _detail = widget.api.getRoute(widget.routeId));

  Future<void> _start() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            DeliveryScreen(api: widget.api, routeId: widget.routeId),
      ),
    );
    if (mounted) _reload();
  }

  void _showStop(Package stop, int number) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListTile(
        leading: _StopPin(number: number, status: stop.status),
        title: Text(stop.addressText ?? 'Sem endereço'),
        subtitle: Text(
          [
            if (stop.city != null) stop.city!,
            packageStatusLabels[stop.status] ?? stop.status,
            if (stop.trackingCode != null) stop.trackingCode!,
          ].join(' • '),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RouteDetail>(
      future: _detail,
      builder: (context, snap) {
        final detail = snap.data;
        return Scaffold(
          appBar: AppBar(title: Text(detail?.route.title ?? 'Mapa da rota')),
          body: snap.hasError
              ? Center(child: Text('Erro ao carregar rota: ${snap.error}'))
              : detail == null
              ? const Center(child: CircularProgressIndicator())
              : _buildMap(detail),
          bottomNavigationBar: detail == null ? null : _buildPanel(detail),
        );
      },
    );
  }

  Widget _buildMap(RouteDetail detail) {
    final stops = detail.stops.where((p) => p.hasCoordinates).toList();
    final start = detail.route.startLat != null && detail.route.startLng != null
        ? LatLng(detail.route.startLat!, detail.route.startLng!)
        : null;
    final points = [?start, for (final p in stops) LatLng(p.lat!, p.lng!)];
    if (points.isEmpty) {
      return const Center(child: Text('Nenhuma parada com localização.'));
    }
    return FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.fromLTRB(48, 48, 48, 48),
          maxZoom: 16,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'br.com.entreggo.entreggo',
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: points,
              strokeWidth: 4,
              color: EntreggoColors.primary.withValues(alpha: 0.7),
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            if (start != null)
              Marker(
                point: start,
                width: 40,
                height: 40,
                child: const _StartPin(),
              ),
            if (_me != null)
              Marker(point: _me!, width: 24, height: 24, child: const _MePin()),
            for (final p in stops.reversed)
              Marker(
                point: LatLng(p.lat!, p.lng!),
                width: 36,
                height: 36,
                child: GestureDetector(
                  onTap: () => _showStop(p, detail.sequence[p.id]!),
                  child: _StopPin(
                    number: detail.sequence[p.id]!,
                    status: p.status,
                  ),
                ),
              ),
          ],
        ),
        const RichAttributionWidget(
          attributions: [TextSourceAttribution('OpenStreetMap contributors')],
        ),
      ],
    );
  }

  Widget _buildPanel(RouteDetail detail) {
    final opt = detail.optimization;
    final km = opt == null
        ? null
        : ((opt['total_distance_m'] as num) / 1000).toStringAsFixed(1);
    final minutes = opt == null
        ? null
        : ((opt['estimated_duration_s'] as num) / 60).round();
    final pending = detail.stops.where((p) => p.status == 'pending').length;
    final started = detail.stops.any((p) => p.status != 'pending');
    final outside = detail.packages.length - detail.stops.length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              [
                '${detail.stops.length} paradas',
                if (km != null) '$km km',
                if (minutes != null) '~${_duration(minutes)}',
              ].join(' • '),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (detail.nextStop != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Próxima: ${detail.nextStop!.addressText ?? 'parada ${detail.sequence[detail.nextStop!.id]}'}',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: EntreggoColors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (outside > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '$outside pacote(s) fora da rota — revise o endereço na lista',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.orange.shade800),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                textStyle: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: pending == 0 ? null : _start,
              icon: const Icon(Icons.navigation),
              label: Text(
                pending == 0
                    ? 'Rota concluída'
                    : started
                    ? 'Continuar entregas ($pending)'
                    : 'Iniciar entregas',
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _duration(int minutes) => minutes < 60
      ? '$minutes min'
      : '${minutes ~/ 60}h${(minutes % 60).toString().padLeft(2, '0')}';
}

class _StopPin extends StatelessWidget {
  const _StopPin({required this.number, required this.status});

  final int number;
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = status == 'pending'
        ? EntreggoColors.primary
        : packageStatusColor(status);
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: Text(
        '$number',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    );
  }
}

/// Ponto azul da posição atual do motorista (estilo Google Maps).
class _MePin extends StatelessWidget {
  const _MePin();

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFF1A73E8),
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 3),
      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
    ),
  );
}

class _StartPin extends StatelessWidget {
  const _StartPin();

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: EntreggoColors.navy,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 3),
      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
    ),
    child: const Icon(Icons.my_location, color: Colors.white, size: 20),
  );
}

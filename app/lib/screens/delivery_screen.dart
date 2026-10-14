import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../routing/location.dart';
import '../routing/navigation.dart';
import '../theme.dart';
import '../widgets/location_picker.dart';
import '../widgets/proof_sheet.dart';
import '../widgets/status.dart';

/// Modo entrega: mostra a próxima parada, abre a navegação e avança ao marcar o status.
class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key, required this.api, required this.routeId});

  final ApiClient api;
  final String routeId;

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  late final Future<RouteDetail> _detail = widget.api.getRoute(widget.routeId);
  bool _busy = false;

  void _toast(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _navigate(NavApp app, Package stop) async {
    final ok = await openNavigation(app, stop.lat!, stop.lng!);
    if (!ok && mounted) _toast('Não foi possível abrir o app de navegação');
  }

  Future<void> _mark(Package stop, String status) async {
    ProofData? proof;
    Future<Position?>? position;
    if (status != 'skipped') {
      // O GPS já começa a ser obtido enquanto o motorista preenche os dados.
      position = currentPosition();
      proof = await showProofSheet(context, delivered: status == 'delivered');
      if (proof == null || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      // O PATCH já confirma o novo status: atualiza o pacote em memória e
      // evita baixar a rota inteira de novo a cada entrega.
      final pos = await position;
      await widget.api.updateStatus(
        stop.id,
        status,
        note: proof?.note,
        recipientName: proof?.recipientName,
        deliveryMethod: proof?.deliveryMethod,
        lat: pos?.latitude,
        lng: pos?.longitude,
      );
      if (proof?.photo case final photo?) {
        try {
          await widget.api.uploadDeliveryPhoto(
            stop.id,
            photo,
            filename: proof?.photoName ?? 'entrega.jpg',
          );
        } catch (_) {
          _toast('Status registrado, mas a foto não foi enviada');
        }
      }
      if (mounted) {
        setState(() => stop.status = status);
        if (status == 'delivered') unawaited(_showDelivered());
      }
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Falha de conexão: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Feedback animado rápido ao concluir a entrega (check + próxima parada).
  Future<void> _showDelivered() async {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (_) => const _DeliveredOverlay(),
    );
    overlay.insert(entry);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    entry.remove();
  }

  /// Posição do pacote no veículo — ajuda a achar a encomenda na parada.
  Future<void> _setLocation(Package pkg) async {
    final picked = await showLocationPicker(
      context,
      current: pkg.vehicleLocation,
    );
    if (picked == null || picked == pkg.vehicleLocation || !mounted) return;
    try {
      await widget.api.updateLocation(pkg.id, picked.isEmpty ? null : picked);
      setState(() => pkg.vehicleLocation = picked.isEmpty ? null : picked);
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Falha de conexão: $e');
    }
  }

  void _showList(RouteDetail detail) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (context, scroll) => ListView(
        controller: scroll,
        children: [
          for (final p in detail.stops)
            _StopTile(
              pkg: p,
              number: detail.sequence[p.id]!,
              isNext: identical(p, detail.nextStop),
              eta: detail.etas[p.id],
            ),
        ],
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
          appBar: AppBar(
            title: const Text('Modo entrega'),
            actions: [
              if (detail != null)
                IconButton(
                  tooltip: 'Ver todas as paradas',
                  icon: const Icon(Icons.format_list_numbered),
                  onPressed: () => _showList(detail),
                ),
            ],
          ),
          body: snap.hasError
              ? Center(child: Text('Erro ao carregar rota: ${snap.error}'))
              : detail == null
              ? const Center(child: CircularProgressIndicator())
              : _buildBody(detail),
        );
      },
    );
  }

  Widget _buildBody(RouteDetail detail) {
    final stops = detail.stops;
    final next = stops.where((p) => p.status == 'pending').firstOrNull;
    if (next == null) return _buildFinished(detail);
    final position = stops.indexOf(next) + 1;
    final done = stops.where((p) => p.status != 'pending').length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(
              value: stops.isEmpty ? 0 : done / stops.length,
              minHeight: 8,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$done de ${stops.length} concluídas',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (detail.remainingSeconds != null)
                  Text(
                    [
                      '${stops.length - done} restantes',
                      '≈ ${_duration(detail.remainingSeconds!)}',
                    ].join(' • '),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PARADA $position DE ${stops.length}',
                      style: const TextStyle(
                        color: EntreggoColors.primary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      next.addressText ?? 'Sem endereço',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (next.city != null)
                          next.state != null
                              ? '${next.city}/${next.state}'
                              : next.city!,
                        if (next.postalCode != null) 'CEP ${next.postalCode}',
                      ].join(' • '),
                    ),
                    if (next.deliveryNotes != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            size: 18,
                            color: EntreggoColors.slate,
                          ),
                          const SizedBox(width: 6),
                          Expanded(child: Text(next.deliveryNotes!)),
                        ],
                      ),
                    ],
                    if (next.trackingCode != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Pacote ${next.trackingCode}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 12),
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _setLocation(next),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: next.vehicleLocation == null
                              ? Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest
                              : EntreggoColors.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: next.vehicleLocation == null
                              ? Border.all(
                                  color: Theme.of(context).dividerColor,
                                )
                              : null,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.local_shipping_outlined,
                              size: 20,
                              color: next.vehicleLocation == null
                                  ? EntreggoColors.slate
                                  : EntreggoColors.accent,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                next.vehicleLocation ??
                                    'Onde está no veículo? Toque para definir',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: next.vehicleLocation == null
                                      ? EntreggoColors.slate
                                      : null,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.edit_outlined,
                              size: 16,
                              color: EntreggoColors.slate,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _navigate(NavApp.googleMaps, next),
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Google Maps'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF33CCFF),
                      foregroundColor: EntreggoColors.navy,
                    ),
                    onPressed: () => _navigate(NavApp.waze, next),
                    icon: const Icon(Icons.navigation_outlined),
                    label: const Text('Waze'),
                  ),
                ),
              ],
            ),
            const Spacer(),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                minimumSize: const Size.fromHeight(60),
              ),
              onPressed: _busy ? null : () => _mark(next, 'delivered'),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Entregue', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      foregroundColor: Colors.orange.shade800,
                    ),
                    onPressed: _busy
                        ? null
                        : () => _mark(next, 'failed_attempt'),
                    child: const Text('Não entregue'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: _busy ? null : () => _mark(next, 'skipped'),
                    child: const Text('Pular'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinished(RouteDetail detail) {
    int count(String s) => detail.stops.where((p) => p.status == s).length;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified, size: 72, color: Colors.green.shade600),
            const SizedBox(height: 16),
            Text(
              'Rota concluída!',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              'Entregues: ${count('delivered')} • '
              'Não entregues: ${count('failed_attempt')} • '
              'Puladas: ${count('skipped')}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
              child: const Text('Voltar ao início'),
            ),
          ],
        ),
      ),
    );
  }
}

String _duration(int seconds) {
  final m = (seconds / 60).round();
  return m < 60 ? '$m min' : '${m ~/ 60}h${(m % 60).toString().padLeft(2, '0')}';
}

/// Linha da lista de paradas: a próxima fica em destaque, com o horário
/// estimado; as concluídas mostram o status e o local no veículo.
class _StopTile extends StatelessWidget {
  const _StopTile({
    required this.pkg,
    required this.number,
    required this.isNext,
    this.eta,
  });

  final Package pkg;
  final int number;
  final bool isNext;
  final DateTime? eta;

  @override
  Widget build(BuildContext context) {
    final color = packageStatusColor(pkg.status);
    final tile = ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Text('$number', style: TextStyle(color: color)),
      ),
      title: Text(
        pkg.addressText ?? pkg.trackingCode ?? 'Pacote',
        style: isNext ? const TextStyle(fontWeight: FontWeight.w700) : null,
      ),
      subtitle: Text(
        [
          packageStatusLabels[pkg.status] ?? pkg.status,
          if (pkg.vehicleLocation != null) pkg.vehicleLocation!,
        ].join(' • '),
      ),
      trailing: eta != null
          ? Text(
              '${eta!.hour.toString().padLeft(2, '0')}:'
              '${eta!.minute.toString().padLeft(2, '0')}',
              style: Theme.of(context).textTheme.bodySmall,
            )
          : null,
    );
    if (!isNext) return tile;
    return Card(
      elevation: 0,
      color: EntreggoColors.primary.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: EntreggoColors.primary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(
              'PRÓXIMA',
              style: TextStyle(
                color: EntreggoColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
          tile,
        ],
      ),
    );
  }
}

/// Check animado exibido por ~1,4 s após confirmar a entrega.
class _DeliveredOverlay extends StatefulWidget {
  const _DeliveredOverlay();

  @override
  State<_DeliveredOverlay> createState() => _DeliveredOverlayState();
}

class _DeliveredOverlayState extends State<_DeliveredOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  )..forward();
  late final Animation<double> _scale = CurvedAnimation(
    parent: _controller,
    curve: Curves.elasticOut,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ColoredBox(
        color: Colors.black45,
        child: Center(
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    size: 64,
                    color: Colors.green.shade600,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Entrega confirmada!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Seguindo para a próxima parada',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

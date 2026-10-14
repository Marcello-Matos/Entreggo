import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../routing/location.dart';
import '../routing/navigation.dart';
import '../theme.dart';
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
      if (mounted) setState(() => stop.status = status);
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Falha de conexão: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
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
            ListTile(
              leading: CircleAvatar(
                backgroundColor: packageStatusColor(p.status)
                    .withValues(alpha: 0.12),
                child: Text(
                  '${detail.sequence[p.id]}',
                  style: TextStyle(color: packageStatusColor(p.status)),
                ),
              ),
              title: Text(p.addressText ?? p.trackingCode ?? 'Pacote'),
              subtitle: Text(packageStatusLabels[p.status] ?? p.status),
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
            Text(
              '$done de ${stops.length} concluídas',
              style: Theme.of(context).textTheme.bodySmall,
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

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../theme.dart';
import '../widgets/status.dart';
import 'route_screen.dart';

/// Histórico de rotas: progresso de cada uma, abrir para continuar ou excluir.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<DeliveryRoute>> _routes = widget.api.listRoutes();

  void _reload() => setState(() => _routes = widget.api.listRoutes());

  void _toast(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _open(DeliveryRoute route) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RouteScreen(api: widget.api, routeId: route.id),
      ),
    );
    _reload();
  }

  Future<void> _delete(DeliveryRoute route) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Excluir "${route.title}"?'),
        content: const Text(
          'Todos os pacotes e paradas desta rota serão removidos. '
          'Essa ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.api.deleteRoute(route.id);
      _toast('Rota excluída');
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Falha de conexão: $e');
    }
    _reload();
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Histórico de entregas')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<DeliveryRoute>>(
          future: _routes,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(
                children: [
                  const SizedBox(height: 120),
                  Center(child: Text('Erro ao carregar: ${snap.error}')),
                  TextButton(
                    onPressed: _reload,
                    child: const Text('Tentar novamente'),
                  ),
                ],
              );
            }
            final routes = snap.data!;
            if (routes.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('Nenhuma rota ainda.')),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: routes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final r = routes[i];
                final progress = r.totalPackages == 0
                    ? 0.0
                    : (r.totalPackages - r.pendingPackages) / r.totalPackages;
                return Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _open(r),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 4, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  r.title,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Excluir rota',
                                icon: Icon(
                                  Icons.delete_outline,
                                  color: Colors.red.shade400,
                                ),
                                onPressed: () => _delete(r),
                              ),
                            ],
                          ),
                          Text(
                            '${_date(r.createdAt)} • '
                            '${routeStatusLabels[r.status] ?? r.status}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 6,
                              borderRadius: BorderRadius.circular(6),
                              backgroundColor: EntreggoColors.background,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${r.deliveredPackages} entregues de '
                            '${r.totalPackages} pacotes • '
                            '${r.pendingPackages} pendentes',
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../theme.dart';
import '../widgets/logo.dart';
import '../widgets/status.dart';
import 'route_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api, required this.onSignOut});

  final ApiClient api;
  final VoidCallback onSignOut;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<DeliveryRoute>> _routes = widget.api.listRoutes();
  bool _busy = false;

  void _reload() => setState(() => _routes = widget.api.listRoutes());

  void _toast(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  /// Fluxo principal: cria a rota do dia e vai direto para o scanner.
  Future<void> _startToday() async {
    setState(() => _busy = true);
    try {
      final now = DateTime.now();
      final route = await widget.api.createRoute(
        'Entregas ${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}',
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RouteScreen(
            api: widget.api,
            routeId: route.id,
            startScanning: true,
          ),
        ),
      );
      _reload();
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Falha de conexão: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(DeliveryRoute route) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RouteScreen(api: widget.api, routeId: route.id),
      ),
    );
    _reload();
  }

  Future<void> _deleteRoute(DeliveryRoute route) async {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            EntreggoMark(width: 34),
            SizedBox(width: 10),
            Text('Entreggo', style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sair',
            icon: const Icon(Icons.logout),
            onPressed: widget.onSignOut,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<DeliveryRoute>>(
          future: _routes,
          builder: (context, snap) {
            final routes = snap.data ?? const <DeliveryRoute>[];
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _StartCard(busy: _busy, onStart: _startToday),
                if (snap.hasError) ...[
                  const SizedBox(height: 24),
                  Center(child: Text('Erro ao carregar rotas: ${snap.error}')),
                  TextButton(
                    onPressed: _reload,
                    child: const Text('Tentar novamente'),
                  ),
                ] else if (routes.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Continuar uma rota',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  for (final route in routes)
                    Card(
                      child: ListTile(
                        title: Text(route.title),
                        subtitle: Text(
                          routeStatusLabels[route.status] ?? route.status,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Excluir rota',
                              icon: Icon(
                                Icons.delete_outline,
                                color: Colors.red.shade400,
                              ),
                              onPressed: () => _deleteRoute(route),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () => _open(route),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StartCard extends StatelessWidget {
  const _StartCard({required this.busy, required this.onStart});

  final bool busy;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const EntreggoMark(width: 72),
            const SizedBox(height: 16),
            Text(
              'Escaneie os pacotes e o Entreggo monta a rota para você.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Depois é só seguir as paradas no Google Maps ou Waze.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: EntreggoColors.slate),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                textStyle: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: busy ? null : onStart,
              icon: const Icon(Icons.local_shipping_outlined),
              label: const Text('Iniciar entregas de hoje'),
            ),
          ],
        ),
      ),
    );
  }
}

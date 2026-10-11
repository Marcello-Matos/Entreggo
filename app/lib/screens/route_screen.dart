import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../theme.dart';
import '../widgets/status.dart';
import 'scanner_screen.dart';

class RouteScreen extends StatefulWidget {
  const RouteScreen({super.key, required this.api, required this.routeId});

  final ApiClient api;
  final String routeId;

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  late Future<RouteDetail> _detail = widget.api.getRoute(widget.routeId);
  bool _busy = false;

  void _reload() =>
      setState(() => _detail = widget.api.getRoute(widget.routeId));

  void _toast(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _action(Future<String?> Function() run) async {
    setState(() => _busy = true);
    try {
      final message = await run();
      if (message != null) _toast(message);
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Falha de conexão: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
      _reload();
    }
  }

  Future<void> _scan() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerScreen(api: widget.api, routeId: widget.routeId),
      ),
    );
    _reload();
  }

  Future<void> _addManual() async {
    final code = TextEditingController();
    final address = TextEditingController();
    final city = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Adicionar pacote'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: code,
              decoration: const InputDecoration(labelText: 'Código (opcional)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: address,
              decoration: const InputDecoration(labelText: 'Endereço'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: city,
              decoration: const InputDecoration(labelText: 'Cidade'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    String? value(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    await _action(() async {
      await widget.api.addPackage(
        widget.routeId,
        trackingCode: value(code),
        address: value(address),
        city: value(city),
      );
      return 'Pacote adicionado';
    });
  }

  Future<void> _geocode() => _action(() async {
    final r = await widget.api.geocode(widget.routeId);
    return 'Validados: ${r['geocoded']} • Não encontrados: ${r['not_found']}';
  });

  Future<void> _optimize() => _action(() async {
    final r = await widget.api.optimize(widget.routeId);
    final km = ((r['total_distance_m'] as num) / 1000).toStringAsFixed(1);
    final min = ((r['estimated_duration_s'] as num) / 60).round();
    final skipped = (r['skipped_package_ids'] as List).length;
    return 'Rota estimada: $km km • ~$min min'
        '${skipped > 0 ? ' • $skipped sem endereço válido' : ''}';
  });

  Future<void> _changeStatus(Package pkg) async {
    final status = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in packageStatusLabels.entries)
              ListTile(
                leading: Icon(
                  Icons.circle,
                  size: 14,
                  color: packageStatusColor(entry.key),
                ),
                title: Text(entry.value),
                selected: entry.key == pkg.status,
                onTap: () => Navigator.pop(context, entry.key),
              ),
          ],
        ),
      ),
    );
    if (status == null || status == pkg.status) return;
    await _action(() async {
      await widget.api.updateStatus(pkg.id, status);
      return null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RouteDetail>(
      future: _detail,
      builder: (context, snap) {
        final detail = snap.data;
        return Scaffold(
          appBar: AppBar(title: Text(detail?.route.title ?? 'Rota')),
          body: snap.hasError
              ? Center(child: Text('Erro ao carregar rota: ${snap.error}'))
              : detail == null
              ? const Center(child: CircularProgressIndicator())
              : _buildBody(detail),
          bottomNavigationBar: detail == null ? null : _buildActions(detail),
        );
      },
    );
  }

  Widget _buildBody(RouteDetail detail) {
    final packages = detail.orderedPackages;
    final optimization = detail.optimization;
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              title: Text(
                routeStatusLabels[detail.route.status] ?? detail.route.status,
              ),
              subtitle: Text(
                '${packages.length} pacotes'
                '${optimization != null ? ' • ${((optimization['total_distance_m'] as num) / 1000).toStringAsFixed(1)} km estimados' : ''}',
              ),
            ),
          ),
          if (optimization != null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Ordem sugerida por distância estimada. Trânsito e restrições de via podem alterar o resultado.',
                style: TextStyle(color: EntreggoColors.slate, fontSize: 12),
              ),
            ),
          if (packages.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(
                child: Text('Escaneie ou adicione pacotes para começar.'),
              ),
            ),
          for (final pkg in packages)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: EntreggoColors.primary.withValues(
                    alpha: 0.1,
                  ),
                  child: Text(
                    '${detail.sequence[pkg.id] ?? '–'}',
                    style: const TextStyle(color: EntreggoColors.primary),
                  ),
                ),
                title: Text(pkg.addressText ?? pkg.trackingCode ?? 'Pacote'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (pkg.addressText != null && pkg.trackingCode != null)
                      Text(pkg.trackingCode!),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        StatusChip(
                          label: packageStatusLabels[pkg.status] ?? pkg.status,
                          color: packageStatusColor(pkg.status),
                        ),
                        if (pkg.addressStatus != 'ready')
                          StatusChip(
                            label:
                                addressStatusLabels[pkg.addressStatus] ??
                                pkg.addressStatus,
                            color: Colors.orange.shade700,
                          ),
                      ],
                    ),
                  ],
                ),
                onTap: () => _changeStatus(pkg),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActions(RouteDetail detail) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          children: [
            IconButton.filledTonal(
              tooltip: 'Escanear',
              onPressed: _busy ? null : _scan,
              icon: const Icon(Icons.qr_code_scanner),
            ),
            IconButton.filledTonal(
              tooltip: 'Adicionar manualmente',
              onPressed: _busy ? null : _addManual,
              icon: const Icon(Icons.add),
            ),
            IconButton.filledTonal(
              tooltip: 'Validar endereços',
              onPressed: _busy ? null : _geocode,
              icon: const Icon(Icons.fact_check_outlined),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy || detail.packages.isEmpty ? null : _optimize,
                icon: const Icon(Icons.alt_route),
                label: const Text('Otimizar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

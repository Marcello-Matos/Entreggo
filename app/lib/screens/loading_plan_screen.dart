import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../routing/loading_plan.dart';
import '../theme.dart';
import '../widgets/status.dart';

/// Plano de carga: sugere onde colocar cada pacote no veículo.
/// A ÚLTIMA entrega vai no fundo; a PRIMEIRA fica junto à porta —
/// o pacote certo está sempre à mão na hora da parada.
class LoadingPlanScreen extends StatefulWidget {
  const LoadingPlanScreen({super.key, required this.api, required this.detail});

  final ApiClient api;
  final RouteDetail detail;

  @override
  State<LoadingPlanScreen> createState() => _LoadingPlanScreenState();
}

class _LoadingPlanScreenState extends State<LoadingPlanScreen> {
  late VehicleType _vehicle = vehicleTypes[1]; // carro
  bool _busy = false;
  bool _applied = false;

  @override
  void initState() {
    super.initState();
    savedVehicleId().then((id) {
      final v = vehicleTypes.where((v) => v.id == id).firstOrNull;
      if (v != null && mounted) setState(() => _vehicle = v);
    });
  }

  void _select(VehicleType v) {
    setState(() {
      _vehicle = v;
      _applied = false;
    });
    saveVehicleId(v.id);
  }

  Future<void> _apply() async {
    final stops = widget.detail.stops
        .where((p) => p.status == 'pending')
        .toList();
    final assignments = planAssignments(loadingPlan(stops, _vehicle));
    setState(() => _busy = true);
    try {
      await widget.api.setLocations(widget.detail.route.id, assignments);
      for (final p in stops) {
        p.vehicleLocation = assignments[p.id];
      }
      if (mounted) {
        setState(() => _applied = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Locais salvos nos pacotes!')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Falha de conexão: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stops = widget.detail.stops
        .where((p) => p.status == 'pending')
        .toList();
    final plan = loadingPlan(stops, _vehicle);
    final order = planZoneOrder(plan, _vehicle);
    return Scaffold(
      appBar: AppBar(title: const Text('Plano de carga')),
      body: stops.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Monte a rota primeiro para gerar o plano de carga.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Qual veículo você está usando?',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final v in vehicleTypes)
                      ChoiceChip(
                        avatar: Icon(v.icon, size: 18),
                        label: Text(v.name),
                        selected: _vehicle == v,
                        onSelected: (_) => _select(v),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  color: EntreggoColors.accent.withValues(alpha: 0.1),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lightbulb_outline,
                          color: EntreggoColors.accent,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Carregue de baixo para cima: a última entrega '
                            'vai no fundo, a primeira fica junto à porta.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                for (final zone in order)
                  _ZoneCard(
                    zone: zone,
                    packages: plan[zone]!,
                    sequence: widget.detail.sequence,
                  ),
              ],
            ),
      bottomNavigationBar: stops.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                  ),
                  onPressed: _busy || _applied ? null : _apply,
                  icon: Icon(
                    _applied ? Icons.check : Icons.inventory_2_outlined,
                  ),
                  label: Text(
                    _applied
                        ? 'Locais aplicados aos pacotes'
                        : 'Aplicar locais aos pacotes',
                  ),
                ),
              ),
            ),
    );
  }
}

class _ZoneCard extends StatelessWidget {
  const _ZoneCard({
    required this.zone,
    required this.packages,
    required this.sequence,
  });

  final String zone;
  final List<Package> packages;
  final Map<String, int> sequence;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.place_outlined,
                  size: 20,
                  color: EntreggoColors.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    zone.toUpperCase(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                StatusChip(
                  label:
                      '${packages.length} ${packages.length == 1 ? 'pacote' : 'pacotes'}',
                  color: EntreggoColors.slate,
                ),
              ],
            ),
            const Divider(height: 16),
            for (final p in packages)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: EntreggoColors.primary.withValues(
                        alpha: 0.12,
                      ),
                      child: Text(
                        '${sequence[p.id] ?? '–'}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: EntreggoColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        p.addressText ?? p.trackingCode ?? 'Pacote',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

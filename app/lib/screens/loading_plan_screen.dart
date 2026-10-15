import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../routing/loading_plan.dart';
import '../theme.dart';
import '../widgets/status.dart';

/// Plano de carga: o motorista informa o veículo e o app desenha o
/// interior dele indicando onde colocar cada pacote. A ÚLTIMA entrega
/// vai no fundo; a PRIMEIRA fica junto à porta.
class LoadingPlanScreen extends StatefulWidget {
  const LoadingPlanScreen({super.key, required this.api, required this.detail});

  final ApiClient api;
  final RouteDetail detail;

  @override
  State<LoadingPlanScreen> createState() => _LoadingPlanScreenState();
}

class _LoadingPlanScreenState extends State<LoadingPlanScreen> {
  late VehicleType _vehicle = vehicleTypes[1]; // carro
  final _modelCtrl = TextEditingController();
  bool _busy = false;
  bool _applied = false;

  @override
  void initState() {
    super.initState();
    savedVehicleId().then((id) {
      final v = vehicleTypes.where((v) => v.id == id).firstOrNull;
      if (v != null && mounted) setState(() => _vehicle = v);
    });
    savedVehicleModel().then((model) {
      if (model != null && mounted) {
        setState(() => _modelCtrl.text = model);
      }
    });
  }

  @override
  void dispose() {
    _modelCtrl.dispose();
    super.dispose();
  }

  void _select(VehicleType v) {
    setState(() {
      _vehicle = v;
      _applied = false;
    });
    saveVehicle(v.id, _modelCtrl.text.trim());
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Qual veículo você está usando?',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _modelCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nome/modelo do veículo',
              hintText: 'Ex.: Peugeot 208',
              prefixIcon: Icon(Icons.directions_car_filled_outlined),
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              saveVehicle(_vehicle.id, v.trim());
              setState(() {});
            },
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
          if (stops.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Text(
                'Monte a rota para ver onde colocar cada pacote.',
                textAlign: TextAlign.center,
              ),
            )
          else ...[
            _VehicleDiagram(
              vehicle: _vehicle,
              model: _modelCtrl.text.trim(),
              plan: plan,
              sequence: widget.detail.sequence,
            ),
            const SizedBox(height: 12),
            Card(
              color: EntreggoColors.accent.withValues(alpha: 0.1),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.lightbulb_outline, color: EntreggoColors.accent),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Carregue de cima para baixo no desenho: a '
                        'última entrega vai no fundo, a primeira fica '
                        'junto à porta.',
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
}

/// Desenho do veículo visto de cima/trás: cabine no topo, área de carga
/// abaixo com cada zona mostrando as paradas que vão nela.
class _VehicleDiagram extends StatelessWidget {
  const _VehicleDiagram({
    required this.vehicle,
    required this.model,
    required this.plan,
    required this.sequence,
  });

  final VehicleType vehicle;
  final String model;
  final Map<String, List<Package>> plan;
  final Map<String, int> sequence;

  @override
  Widget build(BuildContext context) {
    final title = model.isEmpty ? vehicle.name : model;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 10),
          if (vehicle.id != 'moto') ...[
            const _Cabine(),
            const SizedBox(height: 6),
          ],
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: EntreggoColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: EntreggoColors.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              children: [
                for (final row in vehicle.diagramRows)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final zone in row)
                        Expanded(
                          child: _ZoneBox(
                            zone: zone,
                            packages: plan[zone] ?? const [],
                            sequence: sequence,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.arrow_downward,
                size: 16,
                color: EntreggoColors.accent,
              ),
              const SizedBox(width: 4),
              Text(
                '${vehicle.doorLabel} — carregue daqui',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: EntreggoColors.accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bloco da cabine (bancos da frente) — decorativo, não recebe carga.
class _Cabine extends StatelessWidget {
  const _Cabine();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Seat(label: 'Motorista', icon: Icons.drive_eta_outlined),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _Seat(label: 'Passageiro', icon: Icons.event_seat_outlined),
          ),
        ],
      ),
    );
  }
}

class _Seat extends StatelessWidget {
  const _Seat({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 14, color: EntreggoColors.slate),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: EntreggoColors.slate),
        ),
      ],
    );
  }
}

/// Uma zona de carga no desenho: nome + números das paradas que vão ali.
class _ZoneBox extends StatelessWidget {
  const _ZoneBox({
    required this.zone,
    required this.packages,
    required this.sequence,
  });

  final String zone;
  final List<Package> packages;
  final Map<String, int> sequence;

  @override
  Widget build(BuildContext context) {
    final hasPackages = packages.isNotEmpty;
    return Container(
      margin: const EdgeInsets.all(2),
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minHeight: 56),
      decoration: BoxDecoration(
        color: hasPackages
            ? EntreggoColors.primary.withValues(alpha: 0.15)
            : Theme.of(context).dividerColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasPackages
              ? EntreggoColors.primary.withValues(alpha: 0.5)
              : Theme.of(context).dividerColor,
        ),
      ),
      child: Column(
        children: [
          Text(
            _shortZone(zone),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: hasPackages
                  ? EntreggoColors.primary
                  : EntreggoColors.slate,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 3,
            runSpacing: 3,
            alignment: WrapAlignment.center,
            children: [
              for (final p in packages)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: EntreggoColors.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${sequence[p.id] ?? '–'}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              if (!hasPackages)
                const Icon(
                  Icons.check_circle_outline,
                  size: 12,
                  color: EntreggoColors.slate,
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _shortZone(String z) => z
      .replaceAll('Porta-malas ', 'PM ')
      .replaceAll('Baú — ', '')
      .replaceAll('esquerdo', 'esq')
      .replaceAll('direito', 'dir')
      .replaceAll('esquerda', 'esq')
      .replaceAll('direita', 'dir')
      .replaceAll('centro', 'centro');
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

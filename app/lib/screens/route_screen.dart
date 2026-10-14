import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../routing/route_builder.dart';
import '../scanning/label_capture.dart';
import '../theme.dart';
import '../widgets/address_form.dart';
import '../widgets/location_picker.dart';
import '../widgets/status.dart';
import 'map_screen.dart';
import 'scanner_screen.dart';

class RouteScreen extends StatefulWidget {
  const RouteScreen({
    super.key,
    required this.api,
    required this.routeId,
    this.startScanning = false,
  });

  final ApiClient api;
  final String routeId;

  /// Abre o scanner assim que a tela aparece (rota recém-criada).
  final bool startScanning;

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  late Future<RouteDetail> _detail = widget.api.getRoute(widget.routeId);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.startScanning) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
    }
  }

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

  Future<void> _buildAndStart() async {
    setState(() => _busy = true);
    final ok = await buildRoute(context, widget.api, widget.routeId);
    if (!mounted) return;
    setState(() => _busy = false);
    _reload();
    if (ok) await _openMap();
  }

  /// Mapa com as paradas numeradas; de lá o botão "Iniciar" abre a navegação.
  Future<void> _openMap() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapScreen(api: widget.api, routeId: widget.routeId),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _importSpreadsheet() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Lista de pacotes (planilha ou PDF)',
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx', 'pdf'],
    );
    if (files.isEmpty) return;
    final file = files.first;
    await _action(() async {
      final summary = await widget.api.importFile(
        widget.routeId,
        file.name,
        await file.readAsBytes(),
      );
      final errors = (summary['errors'] as List?)?.length ?? 0;
      return 'Importados: ${summary['imported']} • '
          'Duplicados: ${summary['duplicates']}'
          '${errors > 0 ? ' • Erros: $errors' : ''}';
    });
  }

  Future<void> _addManual() async {
    final address = await showAddressForm(context, title: 'Novo pacote');
    if (address == null) return;
    await _action(() async {
      await widget.api.addPackage(widget.routeId, address: address);
      return 'Pacote adicionado';
    });
  }

  Future<void> _renameRoute(String currentTitle) async {
    final controller = TextEditingController(text: currentTitle);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renomear rota'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Título'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) Navigator.pop(context, text);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (title == null || title == currentTitle) return;
    await _action(() async {
      await widget.api.renameRoute(widget.routeId, title);
      return 'Rota renomeada';
    });
  }

  Future<void> _deleteRoute(String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Excluir "$title"?'),
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
    if (confirmed != true || !mounted) return;
    try {
      await widget.api.deleteRoute(widget.routeId);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Falha de conexão: $e');
    }
  }

  Future<void> _deletePackage(Package pkg) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover pacote?'),
        content: Text(
          pkg.addressText ?? pkg.trackingCode ?? 'Pacote sem identificação',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _action(() async {
      await widget.api.deletePackage(pkg.id);
      return 'Pacote removido';
    });
  }

  /// Mostra o formulário de endereço e salva. Retorna `true` se salvou.
  Future<bool> _editAddress(Package pkg, {bool fromPhoto = false}) async {
    final label = fromPhoto ? await captureLabel(context) : null;
    if ((fromPhoto && label == null) || !mounted) return false;
    final address = await showAddressForm(
      context,
      title: pkg.addressText == null
          ? 'Informar endereço'
          : 'Corrigir endereço',
      label: label,
      package: label == null ? pkg : null,
    );
    if (address == null) return false;
    var saved = false;
    await _action(() async {
      await widget.api.updateAddress(pkg.id, address);
      saved = true;
      return 'Endereço salvo';
    });
    return saved;
  }

  /// Percorre um a um os pacotes sem endereço válido, já abrindo o próximo
  /// formulário ao salvar — sem precisar voltar à lista a cada correção.
  Future<void> _reviewPending() async {
    var count = 0;
    var cancelled = false;
    while (!cancelled && mounted) {
      final detail = await _detail;
      final pending = detail.packages
          .where((p) => p.addressStatus != 'ready' && p.status == 'pending')
          .toList();
      if (pending.isEmpty) break;
      final saved = await _editAddress(pending.first);
      if (!saved) {
        cancelled = true;
      } else {
        count++;
      }
    }
    if (!mounted) return;
    _reload();
    _toast(
      count == 0
          ? 'Revisão cancelada'
          : '$count endereço(s) revisado(s). Toque em "Montar rota".',
    );
  }

  /// Posição do pacote no veículo (organização na hora de achar a encomenda).
  Future<void> _setLocation(Package pkg) async {
    final picked = await showLocationPicker(
      context,
      current: pkg.vehicleLocation,
    );
    if (picked == null || picked == pkg.vehicleLocation) return;
    await _action(() async {
      await widget.api.updateLocation(pkg.id, picked.isEmpty ? null : picked);
      pkg.vehicleLocation = picked.isEmpty ? null : picked;
      return picked.isEmpty ? 'Local removido' : 'Local: $picked';
    });
  }

  Future<void> _packageMenu(Package pkg) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('Fotografar etiqueta'),
              onTap: () => Navigator.pop(context, 'photo'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_location_alt_outlined),
              title: Text(
                pkg.addressText == null
                    ? 'Digitar endereço'
                    : 'Corrigir endereço',
              ),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(
                pkg.vehicleLocation == null
                    ? 'Local no veículo'
                    : 'Local: ${pkg.vehicleLocation}',
              ),
              onTap: () => Navigator.pop(context, 'locate'),
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.red.shade400),
              title: Text(
                'Remover pacote',
                style: TextStyle(color: Colors.red.shade400),
              ),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
            const Divider(),
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
    if (choice == null || choice == pkg.status) return;
    if (choice == 'delete') return _deletePackage(pkg);
    if (choice == 'photo' || choice == 'edit') {
      await _editAddress(pkg, fromPhoto: choice == 'photo');
      return;
    }
    if (choice == 'locate') {
      await _setLocation(pkg);
      return;
    }
    await _action(() async {
      await widget.api.updateStatus(pkg.id, choice);
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
          appBar: AppBar(
            title: Text(detail?.route.title ?? 'Rota'),
            actions: [
              PopupMenuButton<String>(
                onSelected: (v) {
                  switch (v) {
                    case 'import':
                      _importSpreadsheet();
                    case 'manual':
                      _addManual();
                    case 'rename' when detail != null:
                      _renameRoute(detail.route.title);
                    case 'delete' when detail != null:
                      _deleteRoute(detail.route.title);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'import',
                    child: ListTile(
                      leading: Icon(Icons.upload_file),
                      title: Text('Importar planilha'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'manual',
                    child: ListTile(
                      leading: Icon(Icons.add_location_alt_outlined),
                      title: Text('Adicionar manualmente'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'rename',
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Renomear rota'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(
                        Icons.delete_outline,
                        color: Colors.red.shade400,
                      ),
                      title: Text(
                        'Excluir rota',
                        style: TextStyle(color: Colors.red.shade400),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
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
    final missing = detail.missingAddress;
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _Stat(value: '${packages.length}', label: 'pacotes'),
                  _Stat(
                    value: '$missing',
                    label: 'sem endereço',
                    color: missing > 0 ? Colors.orange.shade700 : null,
                  ),
                  _Stat(
                    value: optimization == null
                        ? '–'
                        : ((optimization['total_distance_m'] as num) / 1000)
                              .toStringAsFixed(1),
                    label: 'km estimados',
                  ),
                ],
              ),
            ),
          ),
          if (missing > 0)
            Card(
              color: Colors.orange.shade50,
              child: ListTile(
                leading: Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange.shade800,
                ),
                title: Text(
                  missing == 1
                      ? '1 endereço precisa de revisão'
                      : '$missing endereços precisam de revisão',
                ),
                subtitle: const Text('Corrige um a um, sem voltar à lista'),
                trailing: TextButton(
                  onPressed: _busy ? null : _reviewPending,
                  child: const Text('Revisar'),
                ),
              ),
            ),
          if (packages.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Column(
                children: [
                  Icon(
                    Icons.qr_code_scanner,
                    size: 56,
                    color: EntreggoColors.slate,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Escaneie os pacotes para montar a rota.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
              child: Text(
                detail.isOptimized
                    ? 'Ordem de entrega sugerida'
                    : 'Pacotes escaneados',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          for (final pkg in packages)
            Card(
              elevation: 0,
              shape: pkg == detail.nextStop
                  ? RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(
                        color: EntreggoColors.primary,
                        width: 1.5,
                      ),
                    )
                  : null,
              child: ListTile(
                onTap: () => _packageMenu(pkg),
                leading: CircleAvatar(
                  backgroundColor: EntreggoColors.primary.withValues(
                    alpha: 0.1,
                  ),
                  child: Text(
                    '${detail.sequence[pkg.id] ?? '–'}',
                    style: const TextStyle(color: EntreggoColors.primary),
                  ),
                ),
                title: Text(
                  pkg.addressText ?? 'Sem endereço — toque para fotografar',
                  style: pkg.addressText == null
                      ? TextStyle(color: Colors.orange.shade800)
                      : null,
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (pkg.trackingCode != null)
                        Text(
                          pkg.trackingCode!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (pkg == detail.nextStop)
                        const StatusChip(
                          label: 'PRÓXIMA',
                          color: EntreggoColors.primary,
                        ),
                      StatusChip(
                        label: packageStatusLabels[pkg.status] ?? pkg.status,
                        color: packageStatusColor(pkg.status),
                      ),
                      GestureDetector(
                        onTap: () => _setLocation(pkg),
                        child: StatusChip(
                          label: pkg.vehicleLocation ?? 'Local no veículo',
                          color: pkg.vehicleLocation == null
                              ? Colors.grey.shade600
                              : EntreggoColors.accent,
                        ),
                      ),
                      if (pkg.addressText != null &&
                          pkg.addressStatus != 'ready')
                        StatusChip(
                          label:
                              addressStatusLabels[pkg.addressStatus] ??
                              pkg.addressStatus,
                          color: Colors.orange.shade700,
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActions(RouteDetail detail) {
    final pending = detail.stops.where((p) => p.status == 'pending').length;
    final canDeliver = detail.isOptimized && pending > 0;
    final started = detail.stops.any((p) => p.status != 'pending');
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: detail.packages.isEmpty
            ? FilledButton.icon(
                onPressed: _busy ? null : _scan,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Escanear pacotes'),
              )
            : Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Escanear mais pacotes',
                    iconSize: 26,
                    onPressed: _busy ? null : _scan,
                    icon: const Icon(Icons.qr_code_scanner),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: canDeliver
                        ? FilledButton.icon(
                            onPressed: _busy ? null : _openMap,
                            icon: const Icon(Icons.map_outlined),
                            label: Text(
                              started
                                  ? 'Ver mapa e continuar ($pending)'
                                  : 'Ver mapa e iniciar',
                            ),
                          )
                        : FilledButton.icon(
                            onPressed: _busy ? null : _buildAndStart,
                            icon: const Icon(Icons.alt_route),
                            label: const Text('Montar rota'),
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.color});

  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: color ?? EntreggoColors.navy,
          ),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

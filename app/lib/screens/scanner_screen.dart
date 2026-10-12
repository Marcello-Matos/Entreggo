import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../scanning/label_capture.dart';
import '../scanning/label_parser.dart';
import '../theme.dart';
import '../widgets/address_form.dart';

/// Escaneia pacotes: lê o código de barras/QR e, quando o código não tem endereço
/// (não veio de planilha), fotografa a etiqueta para ler o endereço impresso.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key, required this.api, required this.routeId});

  final ApiClient api;
  final String routeId;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final _seen = <String>{};
  int _added = 0;
  bool _busy = false;
  String? _lastMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _show(String message) {
    setState(() => _lastMessage = message);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  Future<T?> _guard<T>(Future<T> Function() action) async {
    setState(() => _busy = true);
    try {
      return await action();
    } on ApiException catch (e) {
      _show(e.isDuplicate ? 'Pacote já escaneado' : e.message);
    } catch (e) {
      _show('Falha de conexão: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return null;
  }

  /// Câmera do scanner precisa ser liberada para a câmera de foto.
  Future<ParsedLabel?> _photo(ImageSource source) async {
    await _controller.stop();
    try {
      if (!mounted) return null;
      return await captureLabel(context, source: source);
    } finally {
      if (mounted) await _controller.start();
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final code = capture.barcodes
        .map((b) => b.rawValue?.trim())
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (code == null || _busy || !_seen.add(code)) return;

    final pkg = await _guard(() => widget.api.scan(widget.routeId, code));
    if (pkg == null) return;
    setState(() => _added++);
    if (pkg.addressText != null) {
      _show('$code — ${pkg.displayAddress}');
      return;
    }
    if (!mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Pacote $code adicionado',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              const Text(
                'O código não traz o endereço. Fotografe a etiqueta para ler o endereço impresso.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, 'camera'),
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text('Fotografar etiqueta'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.pop(context, 'type'),
                child: const Text('Digitar endereço'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Depois'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null) return;
    await _fillAddress(pkg, choice == 'camera');
  }

  Future<void> _fillAddress(Package pkg, bool fromPhoto) async {
    final label = fromPhoto ? await _photo(ImageSource.camera) : null;
    if ((fromPhoto && label == null) || !mounted) return;
    final address = await showAddressForm(context, label: label);
    if (address == null) return;
    await _guard(() => widget.api.updateAddress(pkg.id, address));
    _show('Endereço salvo: ${address.address}');
  }

  /// Etiqueta sem código legível: cria o pacote direto pelo endereço.
  Future<void> _newFromLabel(ImageSource? source) async {
    final label = source == null ? null : await _photo(source);
    if ((source != null && label == null) || !mounted) return;
    final address = await showAddressForm(
      context,
      title: 'Novo pacote',
      label: label,
    );
    if (address == null) return;
    final pkg = await _guard(
      () => widget.api.addPackage(
        widget.routeId,
        trackingCode: label?.trackingCode,
        address: address,
      ),
    );
    if (pkg == null) return;
    setState(() => _added++);
    _show('Adicionado: ${pkg.displayAddress}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Escanear pacotes ($_added)'),
        actions: [
          IconButton(
            tooltip: 'Lanterna',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: _controller.toggleTorch,
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? 'Permissão de câmera negada. Habilite nas configurações do aparelho.'
                      : 'Câmera indisponível. Use "Galeria" ou "Digitar".',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 280,
              height: 180,
              decoration: BoxDecoration(
                border: Border.all(color: EntreggoColors.accent, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          if (_busy) const Center(child: CircularProgressIndicator()),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _lastMessage ?? 'Aponte para o código de barras do pacote ou fotografe a etiqueta.',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _newFromLabel(ImageSource.camera),
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text('Fotografar etiqueta'),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _newFromLabel(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Galeria'),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _busy ? null : () => _newFromLabel(null),
                      icon: const Icon(Icons.keyboard_outlined),
                      label: const Text('Digitar'),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => Navigator.pop(context, _added),
                      icon: const Icon(Icons.check),
                      label: const Text('Concluir'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

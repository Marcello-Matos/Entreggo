import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../api/api_client.dart';

/// Leitura contínua de códigos de barras/QR. O código é salvo apenas como identificador.
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final code = capture.barcodes
        .map((b) => b.rawValue?.trim())
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (code == null || _busy || _seen.contains(code)) return;
    _seen.add(code);
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api.scan(widget.routeId, code);
      setState(() => _added++);
      messenger.showSnackBar(SnackBar(content: Text('Adicionado: $code')));
    } on ApiException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.isDuplicate ? 'Já cadastrado: $code' : e.message),
        ),
      );
      if (!e.isDuplicate) _seen.remove(code);
    } catch (e) {
      _seen.remove(code);
      messenger.showSnackBar(SnackBar(content: Text('Falha de conexão: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Escanear pacotes ($_added)'),
        actions: [
          IconButton(
            tooltip: 'Lanterna',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: _controller.toggleTorch,
          ),
        ],
      ),
      body: MobileScanner(
        controller: _controller,
        onDetect: _onDetect,
        errorBuilder: (context, error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              error.errorCode == MobileScannerErrorCode.permissionDenied
                  ? 'Permissão de câmera negada. Habilite nas configurações do aparelho.'
                  : 'Não foi possível abrir a câmera (${error.errorCode.name}).',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: () => Navigator.pop(context, _added),
            child: const Text('Concluir'),
          ),
        ),
      ),
    );
  }
}

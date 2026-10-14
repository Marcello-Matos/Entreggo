import 'package:flutter/material.dart';

import '../api/api_client.dart';
import 'location.dart';

/// "Montar rota": valida os endereços, obtém a posição atual e calcula a ordem das paradas.
/// Retorna `true` quando a rota foi otimizada.
Future<bool> buildRoute(
  BuildContext context,
  ApiClient api,
  String routeId,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final step = ValueNotifier('Validando endereços...');
  final progress = _ProgressDialog.open(context, step);
  try {
    final geo = await api.geocode(routeId);
    final notFound = (geo['not_found'] as int) + (geo['pending'] as int);
    if (notFound > 0) {
      progress.hide();
      if (!context.mounted) return false;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            notFound == 1
                ? '1 endereço não encontrado'
                : '$notFound endereços não encontrados',
          ),
          content: const Text(
            'Eles ficarão fora da rota até serem corrigidos. Os pacotes aparecem marcados na lista.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Corrigir agora'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
      if (proceed != true || !context.mounted) return false;
      progress.show(context);
    }

    step.value = 'Obtendo sua localização...';
    final position = await currentPosition();
    String? startAddress;
    if (position == null) {
      progress.hide();
      if (!context.mounted) return false;
      startAddress = await _askStartAddress(context);
      if (startAddress == null || !context.mounted) return false;
      progress.show(context);
    }

    step.value = 'Calculando a melhor ordem...';
    final result = await api.optimize(
      routeId,
      startLat: position?.latitude,
      startLng: position?.longitude,
      startAddress: startAddress,
    );
    final km = ((result['total_distance_m'] as num) / 1000).toStringAsFixed(1);
    final stops = (result['stops'] as List).length;
    messenger.showSnackBar(
      SnackBar(content: Text('Rota pronta: $stops paradas • ~$km km')),
    );
    return true;
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Falha de conexão: $e')));
    return false;
  } finally {
    progress.hide();
    step.dispose();
  }
}

Future<String?> _askStartAddress(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('De onde você vai sair?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Não consegui obter sua localização. Ative a localização ou informe o endereço de partida.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Endereço de partida',
              hintText: 'Rua, número, cidade',
            ),
          ),
        ],
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
          child: const Text('Continuar'),
        ),
      ],
    ),
  );
}

class _ProgressDialog {
  _ProgressDialog._(this._step);

  final ValueNotifier<String> _step;
  NavigatorState? _navigator;

  static _ProgressDialog open(
    BuildContext context,
    ValueNotifier<String> step,
  ) => _ProgressDialog._(step)..show(context);

  void show(BuildContext context) {
    if (_navigator != null) return;
    _navigator = Navigator.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(
                child: ValueListenableBuilder(
                  valueListenable: _step,
                  builder: (_, text, _) => Text(text),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void hide() {
    _navigator?.pop();
    _navigator = null;
  }
}

import 'package:flutter/material.dart';

import '../routing/loading_plan.dart';
import '../theme.dart';

/// Pergunta qual veículo o motorista vai usar (chamada logo após a
/// importação). Modelo livre ("Peugeot 208") + categoria para o desenho.
Future<void> showVehiclePicker(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _VehiclePickerSheet(),
  );
}

class _VehiclePickerSheet extends StatefulWidget {
  const _VehiclePickerSheet();

  @override
  State<_VehiclePickerSheet> createState() => _VehiclePickerSheetState();
}

class _VehiclePickerSheetState extends State<_VehiclePickerSheet> {
  late VehicleType _vehicle = vehicleTypes[1];
  final _modelCtrl = TextEditingController();

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

  void _confirm() {
    saveVehicle(_vehicle.id, _modelCtrl.text.trim());
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.local_shipping_outlined,
                color: EntreggoColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Qual veículo você está usando?',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _modelCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Ex.: Peugeot 208',
              labelText: 'Modelo do veículo',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in vehicleTypes)
                ChoiceChip(
                  avatar: Icon(v.icon, size: 18),
                  label: Text(v.name),
                  selected: _vehicle == v,
                  onSelected: (_) => setState(() => _vehicle = v),
                ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: _confirm,
            icon: const Icon(Icons.check),
            label: const Text('Continuar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Agora não'),
          ),
        ],
      ),
    );
  }
}

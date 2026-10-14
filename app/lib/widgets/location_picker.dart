import 'package:flutter/material.dart';

import '../theme.dart';

/// Posições físicas do pacote dentro do veículo, como no fluxo
/// "Where is this package located?" — uma escolha por grupo.
const _positions = ['Fundo', 'Frente'];
const _sides = ['Esquerda', 'Centro', 'Direita'];
const _levels = ['Chão', 'Prateleira'];

/// Abre o seletor "Onde está este pacote?".
/// Retorna o local ("Fundo • Centro • Prateleira"), `''` para limpar
/// o local atual ou `null` se o motorista cancelar.
Future<String?> showLocationPicker(BuildContext context, {String? current}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => _LocationPicker(current: current),
  );
}

class _LocationPicker extends StatefulWidget {
  const _LocationPicker({this.current});

  final String? current;

  @override
  State<_LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<_LocationPicker> {
  String? _position;
  String? _side;
  String? _level;

  @override
  void initState() {
    super.initState();
    final parts = (widget.current ?? '')
        .split('•')
        .map((p) => p.trim())
        .toList();
    if (parts.length == 3) {
      _position = parts[0];
      _side = parts[1];
      _level = parts[2];
    }
  }

  String? get _location {
    if (_position == null || _side == null || _level == null) return null;
    return '$_position • $_side • $_level';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Onde está este pacote no veículo?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            _Group(
              options: _positions,
              icons: const [
                Icons.airline_seat_flat,
                Icons.airline_seat_flat_angled,
              ],
              selected: _position,
              onSelect: (v) => setState(() => _position = v),
            ),
            const SizedBox(height: 12),
            _Group(
              options: _sides,
              icons: const [
                Icons.align_horizontal_left,
                Icons.align_horizontal_center,
                Icons.align_horizontal_right,
              ],
              selected: _side,
              onSelect: (v) => setState(() => _side = v),
            ),
            const SizedBox(height: 12),
            _Group(
              options: _levels,
              icons: const [Icons.square_outlined, Icons.shelves],
              selected: _level,
              onSelect: (v) => setState(() => _level = v),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _location == null
                  ? null
                  : () => Navigator.pop(context, _location),
              child: Text(_location ?? 'Escolha posição, lado e nível'),
            ),
            if (widget.current != null)
              TextButton(
                onPressed: () => Navigator.pop(context, ''),
                child: Text(
                  'Remover local (${widget.current})',
                  style: TextStyle(color: Colors.red.shade400),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.options,
    required this.icons,
    required this.selected,
    required this.onSelect,
  });

  final List<String> options;
  final List<IconData> icons;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _OptionTile(
              label: options[i],
              icon: icons[i],
              selected: options[i] == selected,
              onTap: () => onSelect(options[i]),
            ),
          ),
        ],
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? EntreggoColors.primary : null;
    return Material(
      color: selected
          ? EntreggoColors.primary.withValues(alpha: 0.12)
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

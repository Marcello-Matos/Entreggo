import 'package:flutter/material.dart';

import '../theme.dart';

const routeStatusLabels = {
  'draft': 'Rascunho',
  'validated': 'Endereços validados',
  'optimized': 'Otimizada',
  'in_progress': 'Em andamento',
  'completed': 'Concluída',
  'archived': 'Arquivada',
};

const packageStatusLabels = {
  'pending': 'Pendente',
  'delivered': 'Entregue',
  'failed_attempt': 'Tentativa sem sucesso',
  'skipped': 'Ignorada',
};

const addressStatusLabels = {
  'pending_review': 'Endereço a revisar',
  'ready': 'Endereço validado',
  'not_found': 'Endereço não encontrado',
};

Color packageStatusColor(String status) => switch (status) {
  'delivered' => Colors.green.shade600,
  'failed_attempt' => Colors.orange.shade700,
  'skipped' => EntreggoColors.slate,
  _ => EntreggoColors.primary,
};

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}

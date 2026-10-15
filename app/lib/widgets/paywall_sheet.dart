import 'package:flutter/material.dart';

import '../billing/billing_service.dart';
import '../theme.dart';

/// Paywall do plano Pro: R$ 29,90/mês com 7 dias grátis, cobrado pela
/// Google Play. O [billing] já deve estar inicializado (init()).
Future<void> showPaywall(BuildContext context, BillingService billing) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PaywallSheet(billing: billing),
  );
}

class _PaywallSheet extends StatefulWidget {
  const _PaywallSheet({required this.billing});

  final BillingService billing;

  @override
  State<_PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<_PaywallSheet> {
  bool _busy = false;
  String? _price;

  @override
  void initState() {
    super.initState();
    widget.billing.proPrice().then((p) {
      if (mounted) setState(() => _price = p);
    });
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _subscribe() async {
    setState(() => _busy = true);
    final started = await widget.billing.buyPro();
    if (!mounted) return;
    setState(() => _busy = false);
    if (started) {
      Navigator.pop(context);
      _toast('Compra enviada! O Pro libera assim que a Play confirmar.');
    } else {
      _toast(
        'Assinatura ainda indisponível na loja. '
        'Tente de novo em instantes.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.workspace_premium_outlined,
            size: 48,
            color: EntreggoColors.accent,
          ),
          const SizedBox(height: 8),
          Text(
            'Entreggo Pro',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '${_price ?? 'R\$ 29,90'}/mês • 7 dias grátis',
            textAlign: TextAlign.center,
            style: const TextStyle(color: EntreggoColors.slate),
          ),
          const SizedBox(height: 16),
          const _Perk('Rotas de até 300 pacotes por dia'),
          const _Perk('Importação de listas de até 2.000 endereços'),
          const _Perk('Plano de carga do veículo ilimitado'),
          const _Perk('Comprovantes de entrega com foto e GPS'),
          const SizedBox(height: 18),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
            onPressed: _busy ? null : _subscribe,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Assinar com o Google Play'),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    await widget.billing.restore();
                    if (context.mounted) _toast('Compras restauradas');
                  },
            child: const Text('Restaurar compra'),
          ),
        ],
      ),
    );
  }
}

class _Perk extends StatelessWidget {
  const _Perk(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(Icons.check_circle, size: 18, color: Color(0xFF16A34A)),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

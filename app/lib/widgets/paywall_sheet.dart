import 'package:flutter/material.dart';

import '../billing/billing_service.dart';
import '../theme.dart';

/// Tela de assinatura exibida a quem ainda não é Pro: o uso do app exige
/// iniciar o teste de 7 dias grátis da Google Play (mensal R$ 29,90 ou anual
/// R$ 259,90), com cobrança automática no 8º dia. O [billing] já deve estar
/// inicializado (init()); a liberação chega via [BillingService.purchases].
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({
    super.key,
    required this.billing,
    required this.onRestored,
    required this.onSignOut,
  });

  final BillingService billing;
  final VoidCallback onRestored;
  final VoidCallback onSignOut;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  static const _fallback = {
    BillingService.annualId: 'R\$ 259,90',
    BillingService.monthlyId: 'R\$ 29,90',
  };

  bool _busy = false;
  String _selected = BillingService.annualId;
  Map<String, ({String price, bool trial})> _offers = {};

  @override
  void initState() {
    super.initState();
    widget.billing.offers().then((o) {
      if (mounted) setState(() => _offers = o);
    });
  }

  String _price(String id) => _offers[id]?.price ?? _fallback[id]!;

  /// Sem dados da loja assumimos teste disponível (oferta padrão de 7 dias).
  bool get _trial => _offers[_selected]?.trial ?? true;

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _subscribe() async {
    setState(() => _busy = true);
    final started = await widget.billing.buy(_selected);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!started) {
      _toast(
        'Assinatura ainda indisponível na loja. '
        'Tente de novo em instantes.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final period = _selected == BillingService.annualId ? 'ano' : 'mês';
    return Scaffold(
      appBar: AppBar(
        actions: [
          TextButton(onPressed: widget.onSignOut, child: const Text('Sair')),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
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
            const Text(
              'Teste grátis por 7 dias. Escolha seu plano:',
              textAlign: TextAlign.center,
              style: TextStyle(color: EntreggoColors.slate),
            ),
            const SizedBox(height: 16),
            _PlanOption(
              title: 'Anual',
              price: '${_price(BillingService.annualId)}/ano',
              detail: 'Equivale a R\$ 21,66/mês',
              badge: 'Economize 27%',
              selected: _selected == BillingService.annualId,
              onTap: () => setState(() => _selected = BillingService.annualId),
            ),
            const SizedBox(height: 10),
            _PlanOption(
              title: 'Mensal',
              price: '${_price(BillingService.monthlyId)}/mês',
              detail: 'Cancele quando quiser',
              selected: _selected == BillingService.monthlyId,
              onTap: () => setState(() => _selected = BillingService.monthlyId),
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
                  : Text(_trial ? 'Começar 7 dias grátis' : 'Assinar agora'),
            ),
            const SizedBox(height: 10),
            Text(
              _trial
                  ? 'Grátis por 7 dias, depois ${_price(_selected)}/$period. '
                        'A cobrança é feita automaticamente pela Google Play ao '
                        'fim do teste. Cancele quando quiser em Play Store › '
                        'Pagamentos e assinaturas, sem custo durante o teste.'
                  : '${_price(_selected)}/$period com renovação automática pela '
                        'Google Play. Cancele quando quiser em Play Store › '
                        'Pagamentos e assinaturas.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: EntreggoColors.slate),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      await widget.billing.restore();
                      widget.onRestored();
                      if (context.mounted) _toast('Compras restauradas');
                    },
              child: const Text('Restaurar compra'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanOption extends StatelessWidget {
  const _PlanOption({
    required this.title,
    required this.price,
    required this.detail,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String title;
  final String price;
  final String detail;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? EntreggoColors.primary : const Color(0xFFD5DBE5);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color, width: selected ? 2 : 1),
          color: selected
              ? EntreggoColors.primary.withValues(alpha: 0.06)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF16A34A),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            badge!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 12,
                      color: EntreggoColors.slate,
                    ),
                  ),
                ],
              ),
            ),
            Text(price, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
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

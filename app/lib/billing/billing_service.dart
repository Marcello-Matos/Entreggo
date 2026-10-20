import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../api/api_client.dart';

/// Assinaturas Pro no Google Play: "pro_mensal" (R$ 29,90/mês) e
/// "pro_anual" (R$ 259,90/ano), ambas com oferta de 7 dias grátis
/// configurada no Play Console (cartão cadastrado, cobrança no 8º dia).
/// A Play valida a compra no aparelho; nós registramos o token na API para
/// liberar o plano Pro do usuário. A cada abertura, reenviamos o token
/// encontrado — isso também cobre renovações.
class BillingService {
  BillingService(this.api);

  static const monthlyId = 'pro_mensal';
  static const annualId = 'pro_anual';
  static const productIds = {monthlyId, annualId};

  final ApiClient api;
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// Incrementa a cada compra registrada na API (para a tela recarregar).
  final purchases = ValueNotifier<int>(0);

  /// Começa a ouvir compras e sincroniza assinaturas existentes com a API.
  /// Deve ser chamado uma vez, quando o usuário já está logado.
  Future<void> init() async {
    if (!await _iap.isAvailable()) return;
    _sub ??= _iap.purchaseStream.listen(_onPurchases);
    await restore();
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (productIds.contains(p.productID) &&
          (p.status == PurchaseStatus.purchased ||
              p.status == PurchaseStatus.restored)) {
        await _deliver(p);
      }
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
    }
  }

  Future<void> _deliver(PurchaseDetails p) async {
    try {
      await api.registerPlayPurchase(
        p.productID,
        p.verificationData.serverVerificationData,
      );
      purchases.value++;
    } catch (_) {
      // Se a API falhar, o token é reenviado na próxima abertura do app.
    }
  }

  /// Compra a assinatura [productId]. No Android a Play devolve um item por
  /// oferta; o de menor preço (R$ 0) é o teste grátis, que só aparece se o
  /// usuário ainda tiver direito a ele. Retorna false se a loja estiver
  /// indisponível ou o produto não existir (ainda não ativo no Play Console).
  Future<bool> buy(String productId) async {
    if (!await _iap.isAvailable()) return false;
    final resp = await _iap.queryProductDetails({productId});
    if (resp.productDetails.isEmpty) return false;
    final offer = resp.productDetails.reduce(
      (a, b) => a.rawPrice <= b.rawPrice ? a : b,
    );
    return _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: offer),
    );
  }

  /// Recupera assinatura já paga (aparelho novo / reinstalação).
  Future<void> restore() => _iap.restorePurchases();

  /// Preço cheio formatado pela Play por produto (ex.: "R$ 29,90") e se o
  /// usuário tem direito ao teste grátis; vazio se a loja estiver indisponível.
  Future<Map<String, ({String price, bool trial})>> offers() async {
    if (!await _iap.isAvailable()) return {};
    final resp = await _iap.queryProductDetails(productIds);
    return {
      for (final id in productIds)
        if (resp.productDetails.where((d) => d.id == id) case final ds
            when ds.isNotEmpty)
          id: (
            price: ds.reduce((a, b) => a.rawPrice >= b.rawPrice ? a : b).price,
            trial: ds.any((d) => d.rawPrice == 0),
          ),
    };
  }

  void dispose() {
    _sub?.cancel();
    purchases.dispose();
  }
}

import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

import '../api/api_client.dart';

/// Assinatura mensal "pro_mensal" no Google Play (R$ 29,90, 7 dias grátis).
/// A Play valida a compra no aparelho; nós registramos o token na API para
/// liberar o plano Pro do usuário. A cada abertura, reenviamos o token
/// encontrado — isso também cobre renovações mensais.
class BillingService {
  BillingService(this.api);

  static const productId = 'pro_mensal';

  final ApiClient api;
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// Começa a ouvir compras e sincroniza assinaturas existentes com a API.
  /// Deve ser chamado uma vez, quando o usuário já está logado.
  Future<void> init() async {
    if (!await _iap.isAvailable()) return;
    _sub ??= _iap.purchaseStream.listen(_onPurchases);
    await restore();
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.productID == productId &&
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
    } catch (_) {
      // Se a API falhar, o token é reenviado na próxima abertura do app.
    }
  }

  /// Compra a assinatura Pro. Retorna false se a loja estiver indisponível
  /// ou o produto não existir (ainda não configurado no Play Console).
  Future<bool> buyPro() async {
    if (!await _iap.isAvailable()) return false;
    final resp = await _iap.queryProductDetails({productId});
    if (resp.productDetails.isEmpty) return false;
    return _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: resp.productDetails.first),
    );
  }

  /// Recupera assinatura já paga (aparelho novo / reinstalação).
  Future<void> restore() => _iap.restorePurchases();

  /// Preço formatado da Play (ex.: "R$ 29,90/mês"); null se indisponível.
  Future<String?> proPrice() async {
    if (!await _iap.isAvailable()) return null;
    final resp = await _iap.queryProductDetails({productId});
    if (resp.productDetails.isEmpty) return null;
    return resp.productDetails.first.price;
  }

  void dispose() => _sub?.cancel();
}

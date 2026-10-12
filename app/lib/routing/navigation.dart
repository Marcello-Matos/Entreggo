import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

enum NavApp { googleMaps, waze }

/// Abre a navegação até o destino no app escolhido. No iOS tenta o app instalado
/// (esquema próprio); senão usa o link universal, que abre o app ou o navegador.
Future<bool> openNavigation(NavApp app, double lat, double lng) async {
  final dest = '$lat,$lng';
  final (native, web) = switch (app) {
    NavApp.googleMaps => (
      Uri.parse('comgooglemaps://?daddr=$dest&directionsmode=driving'),
      Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$dest&travelmode=driving',
      ),
    ),
    NavApp.waze => (
      Uri.parse('waze://?ll=$dest&navigate=yes'),
      Uri.parse('https://waze.com/ul?ll=$dest&navigate=yes'),
    ),
  };
  if (defaultTargetPlatform == TargetPlatform.iOS &&
      await canLaunchUrl(native)) {
    return launchUrl(native);
  }
  return launchUrl(web, mode: LaunchMode.externalApplication);
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/models.dart';

/// Layout do veículo: as zonas vão da mais funda (carregada primeiro,
/// última entrega) até a mais próxima da porta (primeira entrega).
class VehicleType {
  const VehicleType({
    required this.id,
    required this.name,
    required this.icon,
    required this.zones,
  });

  final String id;
  final String name;
  final IconData icon;
  final List<String> zones;
}

const vehicleTypes = [
  VehicleType(
    id: 'moto',
    name: 'Moto (baú)',
    icon: Icons.two_wheeler,
    zones: ['Baú — fundo', 'Baú — meio', 'Baú — entrada'],
  ),
  VehicleType(
    id: 'carro',
    name: 'Carro',
    icon: Icons.directions_car_outlined,
    zones: [
      'Porta-malas fundo esquerdo',
      'Porta-malas fundo direito',
      'Porta-malas entrada esquerda',
      'Porta-malas entrada direita',
      'Banco traseiro',
      'Banco passageiro',
    ],
  ),
  VehicleType(
    id: 'fiorino',
    name: 'Fiorino / van pequena',
    icon: Icons.airport_shuttle_outlined,
    zones: [
      'Fundo esquerdo',
      'Fundo direito',
      'Fundo centro',
      'Meio esquerdo',
      'Meio direito',
      'Porta esquerda',
      'Porta direita',
    ],
  ),
  VehicleType(
    id: 'van',
    name: 'Van grande',
    icon: Icons.local_shipping_outlined,
    zones: [
      'Fundo esquerdo',
      'Fundo direito',
      'Fundo centro',
      'Meio esquerdo',
      'Meio direito',
      'Meio centro',
      'Porta esquerda',
      'Porta direita',
      'Porta centro',
    ],
  ),
];

const _prefKey = 'vehicle_type';

Future<String?> savedVehicleId() async =>
    (await SharedPreferences.getInstance()).getString(_prefKey);

Future<void> saveVehicleId(String id) async =>
    (await SharedPreferences.getInstance()).setString(_prefKey, id);

/// Sugestão de carga: retorna {zona: [paradas na ordem de entrega]}.
/// A ÚLTIMA parada vai para a zona mais funda (carregada primeiro);
/// a PRIMEIRA fica na zona mais acessível, junto à porta.
/// As zonas são preenchidas uniformemente e na ordem fundo → porta.
Map<String, List<Package>> loadingPlan(
  List<Package> stops,
  VehicleType vehicle,
) {
  final plan = <String, List<Package>>{};
  if (stops.isEmpty) return plan;
  final zones = vehicle.zones;
  // Percorre as paradas de trás para frente (última entrega primeiro)
  // distribuindo pelas zonas da mais funda para a mais próxima.
  final reversed = stops.reversed.toList();
  for (var i = 0; i < reversed.length; i++) {
    // Poucas paradas: uma zona por parada, a partir da mais funda.
    // Muitas paradas: divide uniformemente entre as zonas.
    final zoneIndex = reversed.length <= zones.length
        ? i
        : (i * zones.length) ~/ reversed.length;
    final zone = zones[zoneIndex.clamp(0, zones.length - 1)];
    (plan[zone] ??= []).add(reversed[i]);
  }
  // Dentro de cada zona, reordena pela ordem de entrega (leitura natural).
  for (final list in plan.values) {
    list.sort((a, b) => stops.indexOf(a).compareTo(stops.indexOf(b)));
  }
  return plan;
}

/// Zonas usadas na ordem de carregamento (fundo → porta).
List<String> planZoneOrder(Map<String, List<Package>> plan, VehicleType v) => [
  for (final z in v.zones)
    if (plan.containsKey(z)) z,
];

/// {package_id: zona} para gravar os locais no servidor.
Map<String, String> planAssignments(Map<String, List<Package>> plan) => {
  for (final e in plan.entries)
    for (final p in e.value) p.id: e.key,
};

import 'package:entreggo/api/models.dart';
import 'package:entreggo/routing/loading_plan.dart';
import 'package:flutter_test/flutter_test.dart';

Package _pkg(String id) =>
    Package(id: id, status: 'pending', addressStatus: 'ready');

void main() {
  final car = vehicleTypes.firstWhere((v) => v.id == 'carro');

  test('última parada vai para a zona mais funda, primeira para a porta', () {
    final stops = [_pkg('p1'), _pkg('p2'), _pkg('p3')];
    final plan = loadingPlan(stops, car);
    // 3 paradas, 6 zonas: uma por zona, da mais funda à entrada
    expect(plan['Porta-malas fundo esquerdo']!.single.id, 'p3');
    expect(plan['Porta-malas fundo direito']!.single.id, 'p2');
    expect(plan['Porta-malas entrada esquerda']!.single.id, 'p1');
  });

  test('com mais paradas que zonas, divide uniformemente', () {
    final stops = [for (var i = 0; i < 30; i++) _pkg('p$i')];
    final moto = vehicleTypes.first; // 3 zonas
    final plan = loadingPlan(stops, moto);
    // 30 paradas ÷ 3 zonas = 10 por zona
    expect(plan['Baú — fundo']!.length, 10);
    expect(plan['Baú — meio']!.length, 10);
    expect(plan['Baú — entrada']!.length, 10);
    // a primeira parada está na zona mais acessível
    expect(plan['Baú — entrada']!.first.id, 'p0');
    // a última está no fundo
    expect(plan['Baú — fundo']!.last.id, 'p29');
  });

  test('planAssignments devolve package_id -> zona para todos', () {
    final stops = [_pkg('a'), _pkg('b')];
    final assignments = planAssignments(loadingPlan(stops, car));
    expect(assignments.keys.toSet(), {'a', 'b'});
    expect(assignments.values, isNot(contains(null)));
  });
}

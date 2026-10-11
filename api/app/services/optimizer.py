"""Ordenação de paradas com OR-Tools.

A matriz de custo usa distância em linha reta (haversine). Ela pode ser trocada por uma
matriz de distâncias/tempos de um fornecedor de mapas sem alterar o solver.
"""

import math
from dataclasses import dataclass

from ortools.constraint_solver import pywrapcp, routing_enums_pb2

Point = tuple[float, float]


@dataclass
class OptimizationResult:
    order: list[int]
    total_distance_m: int


class NoSolutionError(Exception):
    pass


def haversine_m(a: Point, b: Point) -> int:
    lat1, lng1, lat2, lng2 = map(math.radians, (*a, *b))
    h = (
        math.sin((lat2 - lat1) / 2) ** 2
        + math.cos(lat1) * math.cos(lat2) * math.sin((lng2 - lng1) / 2) ** 2
    )
    return round(2 * 6_371_000 * math.asin(math.sqrt(h)))


def optimize_order(start: Point, stops: list[Point], time_limit_s: int = 5) -> OptimizationResult:
    """Retorna a ordem sugerida (índices de `stops`) partindo de `start`, sem retorno à origem."""
    if not stops:
        return OptimizationResult(order=[], total_distance_m=0)

    points = [start, *stops]
    n = len(points)
    end = n  # nó fictício de chegada com custo zero: a rota termina na última parada
    matrix = [[haversine_m(p, q) for q in points] + [0] for p in points] + [[0] * (n + 1)]

    manager = pywrapcp.RoutingIndexManager(n + 1, 1, [0], [end])
    routing = pywrapcp.RoutingModel(manager)
    transit = routing.RegisterTransitCallback(
        lambda i, j: matrix[manager.IndexToNode(i)][manager.IndexToNode(j)]
    )
    routing.SetArcCostEvaluatorOfAllVehicles(transit)

    params = pywrapcp.DefaultRoutingSearchParameters()
    params.first_solution_strategy = routing_enums_pb2.FirstSolutionStrategy.PATH_CHEAPEST_ARC
    params.local_search_metaheuristic = (
        routing_enums_pb2.LocalSearchMetaheuristic.GUIDED_LOCAL_SEARCH
    )
    params.time_limit.seconds = time_limit_s

    solution = routing.SolveWithParameters(params)
    if solution is None:
        raise NoSolutionError("O otimizador não encontrou uma solução válida")

    order, index = [], solution.Value(routing.NextVar(routing.Start(0)))
    while not routing.IsEnd(index):
        order.append(manager.IndexToNode(index) - 1)
        index = solution.Value(routing.NextVar(index))
    return OptimizationResult(order=order, total_distance_m=solution.ObjectiveValue())

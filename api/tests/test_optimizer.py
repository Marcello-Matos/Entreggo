from app.services.optimizer import haversine_m, optimize_order


def test_haversine_known_distance():
    # Praça da Sé -> Av. Paulista (MASP): ~3 km
    assert 2500 < haversine_m((-23.5503, -46.6339), (-23.5614, -46.6559)) < 3000


def test_empty_and_single_stop():
    assert optimize_order((0, 0), []).order == []
    assert optimize_order((0, 0), [(0, 0.01)], time_limit_s=1).order == [0]


def test_orders_points_along_a_line():
    start = (0.0, 0.0)
    stops = [(0.0, 0.03), (0.0, 0.01), (0.0, 0.04), (0.0, 0.02)]
    result = optimize_order(start, stops, time_limit_s=1)
    assert result.order == [1, 3, 0, 2]
    assert abs(result.total_distance_m - haversine_m(start, (0.0, 0.04))) < 5

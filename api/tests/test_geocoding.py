import httpx

from app.services import geocoding
from app.services.geocoding import NominatimGeocoder


def _fake_get(payload):
    def fake_get(url, params, headers, timeout):
        assert params["countrycodes"] == "br"
        assert headers["User-Agent"].startswith("Entreggo/")
        return httpx.Response(200, json=payload, request=httpx.Request("GET", url))

    return fake_get


def test_nominatim_hit(monkeypatch):
    monkeypatch.setattr(NominatimGeocoder, "MIN_INTERVAL_S", 0)
    monkeypatch.setattr(
        geocoding.httpx,
        "get",
        _fake_get([{"lat": "-23.55", "lon": "-46.63", "addresstype": "building"}]),
    )
    hit = NominatimGeocoder("http://nominatim.test").geocode("Praça da Sé, São Paulo")
    assert (hit.lat, hit.lng, hit.provider) == (-23.55, -46.63, "nominatim")


def test_nominatim_rejects_vague_or_empty(monkeypatch):
    monkeypatch.setattr(NominatimGeocoder, "MIN_INTERVAL_S", 0)
    geocoder = NominatimGeocoder("http://nominatim.test")
    monkeypatch.setattr(
        geocoding.httpx, "get", _fake_get([{"lat": "1", "lon": "2", "addresstype": "city"}])
    )
    assert geocoder.geocode("São Paulo") is None
    monkeypatch.setattr(geocoding.httpx, "get", _fake_get([]))
    assert geocoder.geocode("Rua que não existe") is None


def test_geocode_fallback_tries_simpler_queries():
    from types import SimpleNamespace

    from app.routers.routes import _geocode_with_fallback
    from app.services.geocoding import GeocodeHit

    calls = []

    class Stub:
        def geocode(self, query):
            calls.append(query)
            if query.startswith("Rua X, 10,") and "01234-567" in query:
                return GeocodeHit(-23.5, -46.6, "ROOFTOP", "fake", "2026-01-01T00:00:00Z")
            return None

    pkg = SimpleNamespace(
        address_text="Rua X, 10 - Bairro, Cidade - SP",
        city=None,
        state=None,
        postal_code="01234-567",
    )
    assert _geocode_with_fallback(Stub(), pkg) is not None
    assert len(calls) == 3  # completo -> rua+cidade -> rua+cep

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


def test_cep_lookup(monkeypatch):
    def fake_get(url, timeout):
        payload = (
            {"lat": "-14.2350040", "lng": "-51.9252800"}  # centro do Brasil = desconhecido
            if "06110002" in url
            else {"lat": "-23.6702405", "lng": "-46.5433941"}
        )
        return httpx.Response(200, json=payload, request=httpx.Request("GET", url))

    monkeypatch.setattr(geocoding.httpx, "get", fake_get)
    hit = geocoding.cep_lookup("09050-130")
    assert (hit.lat, hit.provider) == (-23.6702405, "awesomeapi-cep")
    assert geocoding.cep_lookup("06110-002") is None
    assert geocoding.cep_lookup("123") is None


def test_geocode_falls_back_to_cep():
    from types import SimpleNamespace

    from app.routers.routes import _geocode_with_fallback
    from app.services.geocoding import GeocodeHit

    class Stub:
        def geocode(self, query):
            return None

        def geocode_cep(self, cep):
            return GeocodeHit(-23.6, -46.5, "cep", "fake", "2026-01-01T00:00:00Z")

    pkg = SimpleNamespace(
        address_text="Rua Quirino Motta, 100 - Vila Floresta",
        city="Santo André",
        state="SP",
        postal_code="09050-130",
    )
    assert _geocode_with_fallback(Stub(), pkg).confidence == "cep"


def _photon_feature(name, city, lat=-23.5, lng=-46.7, type_="street"):
    return {
        "geometry": {"coordinates": [lng, lat]},
        "properties": {"name": name, "city": city, "countrycode": "BR", "type": type_},
    }


def test_photon_rejects_same_street_in_other_city_and_wrong_street(monkeypatch):
    features = [
        _photon_feature("Rua Barão de Jaceguai", "São José dos Campos", lat=-23.1),
        _photon_feature("Rua Flor de Liz", "São Paulo", lat=-23.2),
        _photon_feature("Rua Barão de Jaceguai", "São Paulo", lat=-23.62),
    ]

    def fake_get(url, params, headers, timeout):
        return httpx.Response(200, json={"features": features}, request=httpx.Request("GET", url))

    monkeypatch.setattr(geocoding.httpx, "get", fake_get)
    hit = geocoding.photon_lookup("Rua Barão de Jaceguai, 1409", "São Paulo", "SP", None)
    assert (hit.lat, hit.provider) == (-23.62, "photon")
    assert geocoding.photon_lookup("Rua Bartônias, 100", "Osasco", "SP", None) is None


def test_fallback_continues_when_main_provider_is_down():
    from types import SimpleNamespace

    from app.routers.routes import _geocode_with_fallback
    from app.services.geocoding import GeocodeHit

    class Down:
        def geocode(self, query):
            raise httpx.ConnectError("429")

        def geocode_structured(self, street, city, state, cep):
            return GeocodeHit(-23.5, -46.6, "street", "photon", "2026-01-01T00:00:00Z")

    pkg = SimpleNamespace(address_text="Rua A, 1", city="Osasco", state="SP", postal_code=None)
    assert _geocode_with_fallback(Down(), pkg).provider == "photon"

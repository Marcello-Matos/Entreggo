import re
import time
import unicodedata
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Protocol

import httpx
from fastapi import Depends

from app.config import Settings, get_settings


@dataclass
class GeocodeHit:
    lat: float
    lng: float
    confidence: str
    provider: str
    queried_at: str


class Geocoder(Protocol):
    def geocode(self, address: str) -> GeocodeHit | None: ...


class GoogleGeocoder:
    URL = "https://maps.googleapis.com/maps/api/geocode/json"

    def __init__(self, api_key: str):
        self.api_key = api_key

    def geocode_cep(self, postal_code: str) -> GeocodeHit | None:
        return cep_lookup(postal_code)

    def geocode_structured(self, street, city, state, postal_code) -> GeocodeHit | None:
        return photon_lookup(street, city, state, postal_code)

    def geocode(self, address: str) -> GeocodeHit | None:
        resp = httpx.get(
            self.URL,
            params={"address": address, "key": self.api_key, "region": "br", "language": "pt-BR"},
            timeout=10,
        )
        resp.raise_for_status()
        results = resp.json().get("results") or []
        if not results:
            return None
        top = results[0]
        loc = top["geometry"]["location"]
        return GeocodeHit(
            lat=loc["lat"],
            lng=loc["lng"],
            confidence=top["geometry"].get("location_type", "UNKNOWN"),
            provider="google",
            queried_at=datetime.now(UTC).isoformat(),
        )


class NominatimGeocoder:
    """OpenStreetMap (Nominatim). Política de uso: no máximo 1 requisição/s e User-Agent próprio."""

    MIN_INTERVAL_S = 1.1
    BLOCK_PAUSE_S = 600
    TOO_VAGUE = {"country", "state", "region", "county", "municipality", "city", "town"}
    _last_call = 0.0
    _blocked_until = 0.0

    def __init__(self, url: str, contact: str = ""):
        self.url = url
        self.headers = {"User-Agent": f"Entreggo/0.1 ({contact or 'desenvolvimento'})"}

    def geocode_cep(self, postal_code: str) -> GeocodeHit | None:
        return cep_lookup(postal_code)

    def geocode_structured(self, street, city, state, postal_code) -> GeocodeHit | None:
        return photon_lookup(street, city, state, postal_code)

    def geocode(self, address: str) -> GeocodeHit | None:
        # Servidores na nuvem costumam receber 429/403 do Nominatim: depois disso,
        # pausa o serviço por um tempo e deixa os fallbacks trabalharem sem esperar.
        if time.monotonic() < NominatimGeocoder._blocked_until:
            raise httpx.HTTPError("Nominatim temporariamente indisponível")
        wait = NominatimGeocoder._last_call + self.MIN_INTERVAL_S - time.monotonic()
        if wait > 0:
            time.sleep(wait)
        NominatimGeocoder._last_call = time.monotonic()
        try:
            resp = httpx.get(
                self.url,
                params={"q": address, "format": "jsonv2", "countrycodes": "br", "limit": 1},
                headers={**self.headers, "Accept-Language": "pt-BR"},
                timeout=10,
            )
            resp.raise_for_status()
        except httpx.HTTPError:
            NominatimGeocoder._blocked_until = time.monotonic() + self.BLOCK_PAUSE_S
            raise
        results = resp.json()
        if not results or results[0].get("addresstype") in self.TOO_VAGUE:
            return None
        top = results[0]
        return GeocodeHit(
            lat=float(top["lat"]),
            lng=float(top["lon"]),
            confidence=top.get("addresstype", "unknown"),
            provider="nominatim",
            queried_at=datetime.now(UTC).isoformat(),
        )


PHOTON_URL = "https://photon.komoot.io/api/"
_STREET_TYPES = {
    "rua", "r", "avenida", "av", "praca", "pca", "travessa", "tv", "alameda", "al",
    "estrada", "rodovia", "largo", "viela", "beco", "dona", "dom", "doutor", "dr",
}  # fmt: skip


def _norm(text: str | None) -> str:
    plain = unicodedata.normalize("NFKD", text or "").encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9 ]+", " ", plain.lower()).strip()


def _name_tokens(street: str) -> set[str]:
    name = re.sub(r",.*$", "", street)  # tira número e complemento
    return {t for t in _norm(name).split() if len(t) >= 4 and t not in _STREET_TYPES}


def photon_lookup(
    street: str, city: str | None, state: str | None, postal_code: str | None
) -> GeocodeHit | None:
    """Photon (OpenStreetMap, aceita consultas de servidores). Só aceita o resultado
    se a cidade bater e o nome da rua tiver alguma palavra em comum com o pedido,
    para não levar o entregador a uma rua homônima em outra cidade."""
    query = ", ".join(p for p in (street, city, state, postal_code) if p)
    try:
        resp = httpx.get(
            PHOTON_URL,
            params={"q": query, "limit": 5, "bbox": "-74,-34,-34,6"},
            headers={"User-Agent": "Entreggo/0.1"},
            timeout=10,
        )
        resp.raise_for_status()
        features = resp.json().get("features") or []
    except (httpx.HTTPError, ValueError):
        return None
    wanted_city, wanted_name = _norm(city), _name_tokens(street)
    for feature in features:
        props = feature.get("properties") or {}
        if props.get("countrycode") != "BR":
            continue
        found_city = _norm(props.get("city") or props.get("county") or props.get("district"))
        if wanted_city and wanted_city != found_city:
            continue
        found_name = set(_norm(f"{props.get('name', '')} {props.get('street', '')}").split())
        if wanted_name and not wanted_name & found_name:
            continue
        lng, lat = feature["geometry"]["coordinates"]
        return GeocodeHit(
            lat=float(lat),
            lng=float(lng),
            confidence=props.get("type", "unknown"),
            provider="photon",
            queried_at=datetime.now(UTC).isoformat(),
        )
    return None


CEP_URL = "https://cep.awesomeapi.com.br/json/{cep}"
# Coordenada genérica devolvida quando o serviço não sabe localizar o CEP.
_BRAZIL_CENTROID = (-14.235, -51.925)


def cep_lookup(postal_code: str) -> GeocodeHit | None:
    """Último recurso: coordenada do trecho de rua do CEP (sem precisão de número)."""
    digits = "".join(c for c in postal_code if c.isdigit())
    if len(digits) != 8:
        return None
    try:
        resp = httpx.get(CEP_URL.format(cep=digits), timeout=10)
        resp.raise_for_status()
        data = resp.json()
        lat, lng = float(data["lat"]), float(data["lng"])
    except (httpx.HTTPError, KeyError, TypeError, ValueError):
        return None  # fallback opcional: falha aqui não interrompe a validação
    if abs(lat - _BRAZIL_CENTROID[0]) < 0.01 and abs(lng - _BRAZIL_CENTROID[1]) < 0.01:
        return None
    return GeocodeHit(
        lat=lat,
        lng=lng,
        confidence="cep",
        provider="awesomeapi-cep",
        queried_at=datetime.now(UTC).isoformat(),
    )


def full_address(
    address: str, city: str | None = None, state: str | None = None, postal_code: str | None = None
) -> str:
    return ", ".join(p for p in (address, city, state, postal_code, "Brasil") if p)


def get_geocoder(settings: Settings = Depends(get_settings)) -> Geocoder:
    if settings.google_maps_api_key:
        return GoogleGeocoder(settings.google_maps_api_key)
    return NominatimGeocoder(settings.nominatim_url, settings.nominatim_contact)

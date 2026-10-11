from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Protocol

import httpx
from fastapi import Depends, HTTPException, status

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


def full_address(address: str, city: str | None, state: str | None, postal_code: str | None) -> str:
    return ", ".join(p for p in (address, city, state, postal_code, "Brasil") if p)


def get_geocoder(settings: Settings = Depends(get_settings)) -> Geocoder:
    if not settings.google_maps_api_key:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Geocodificação não configurada")
    return GoogleGeocoder(settings.google_maps_api_key)

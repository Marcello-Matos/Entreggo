import os
import uuid

os.environ["DATABASE_URL"] = "sqlite+pysqlite:///:memory:"
os.environ["SUPABASE_JWT_SECRET"] = "test-secret-with-at-least-32-bytes!!"
os.environ["SUPABASE_URL"] = ""
os.environ["GOOGLE_MAPS_API_KEY"] = ""
os.environ["OPTIMIZER_TIME_LIMIT_S"] = "1"

import jwt  # noqa: E402
import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import create_engine  # noqa: E402
from sqlalchemy.orm import sessionmaker  # noqa: E402
from sqlalchemy.pool import StaticPool  # noqa: E402

from app.db import Base, get_db  # noqa: E402
from app.main import app  # noqa: E402
from app.services.geocoding import GeocodeHit, get_geocoder  # noqa: E402


class FakeGeocoder:
    """Endereços contendo 'inexistente' não são encontrados; os demais recebem coordenadas."""

    def __init__(self):
        self.calls = 0

    def geocode(self, address: str):
        self.calls += 1
        if "inexistente" in address.lower():
            return None
        return GeocodeHit(
            lat=-23.55 + self.calls * 0.01,
            lng=-46.63 - self.calls * 0.01,
            confidence="ROOFTOP",
            provider="fake",
            queried_at="2026-01-01T00:00:00+00:00",
        )


@pytest.fixture
def db_session():
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine, expire_on_commit=False)
    with Session() as session:
        yield session


@pytest.fixture
def client(db_session):
    app.dependency_overrides[get_db] = lambda: db_session
    app.dependency_overrides[get_geocoder] = FakeGeocoder
    yield TestClient(app)
    app.dependency_overrides.clear()


def make_token(sub: uuid.UUID | None = None, **claims) -> str:
    payload = {"sub": str(sub or uuid.uuid4()), "aud": "authenticated", **claims}
    return jwt.encode(payload, os.environ["SUPABASE_JWT_SECRET"], algorithm="HS256")


@pytest.fixture
def auth():
    return {"Authorization": f"Bearer {make_token(email='a@entreggo.app')}"}


@pytest.fixture
def other_auth():
    return {"Authorization": f"Bearer {make_token(email='b@entreggo.app')}"}


@pytest.fixture
def route_id(client, auth):
    resp = client.post(
        "/v1/routes",
        json={"title": "Rota teste", "start_lat": -23.55, "start_lng": -46.63},
        headers=auth,
    )
    assert resp.status_code == 201
    return resp.json()["id"]

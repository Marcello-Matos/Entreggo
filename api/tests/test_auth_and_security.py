import time

import pytest
from cryptography.hazmat.primitives.asymmetric import rsa

from tests.conftest import make_token


def _status(client, token):
    return client.get("/v1/routes", headers={"Authorization": f"Bearer {token}"}).status_code


def test_health(client):
    assert client.get("/health").json() == {"status": "ok"}


def test_requires_auth(client):
    assert client.get("/v1/routes").status_code == 401


def test_accepts_valid_firebase_token(client):
    assert _status(client, make_token()) == 200


def test_rejects_bad_signature(client):
    other_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    assert _status(client, make_token(key=other_key)) == 401


@pytest.mark.parametrize(
    "claims",
    [
        {"aud": "outro-projeto"},
        {"iss": "https://securetoken.google.com/outro-projeto"},
        {"exp": int(time.time()) - 10},
        {"sub": ""},
    ],
)
def test_rejects_invalid_claims(client, claims):
    assert _status(client, make_token(**claims)) == 401


def test_user_cannot_access_other_users_route(client, route_id, auth, other_auth):
    pkg = client.post(
        f"/v1/routes/{route_id}/packages", json={"tracking_code": "A1"}, headers=auth
    ).json()

    assert client.get(f"/v1/routes/{route_id}", headers=other_auth).status_code == 404
    assert client.get(f"/v1/routes/{route_id}/summary", headers=other_auth).status_code == 404
    assert (
        client.post(
            f"/v1/routes/{route_id}/scan", json={"code": "B"}, headers=other_auth
        ).status_code
        == 404
    )
    assert (
        client.patch(
            f"/v1/packages/{pkg['id']}/status", json={"status": "delivered"}, headers=other_auth
        ).status_code
        == 404
    )
    assert client.get("/v1/routes", headers=other_auth).json() == []

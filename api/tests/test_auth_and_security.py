import jwt

from tests.conftest import make_token


def test_health(client):
    assert client.get("/health").json() == {"status": "ok"}


def test_requires_auth(client):
    assert client.get("/v1/routes").status_code == 401


def test_rejects_bad_signature(client):
    token = jwt.encode({"sub": "x", "aud": "authenticated"}, "x" * 40, algorithm="HS256")
    assert client.get("/v1/routes", headers={"Authorization": f"Bearer {token}"}).status_code == 401


def test_rejects_wrong_audience(client):
    token = make_token(aud="anon")
    assert client.get("/v1/routes", headers={"Authorization": f"Bearer {token}"}).status_code == 401


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

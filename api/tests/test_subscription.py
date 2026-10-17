"""Trial de 7 dias no cadastro e registro de compra do Google Play."""


def test_new_user_gets_seven_day_trial(client, auth):
    resp = client.get("/v1/subscription", headers=auth)
    assert resp.status_code == 200
    body = resp.json()
    assert body["entitlement"] == "pro"
    assert body["source"] == "trial"
    assert body["product_id"] == "trial_7d"
    assert body["expires_at"] is not None


def test_play_purchase_grants_pro(client, auth):
    resp = client.post(
        "/v1/subscription/play",
        json={"product_id": "pro_mensal", "purchase_token": "token123"},
        headers=auth,
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["entitlement"] == "pro"
    assert body["source"] == "play"
    assert body["product_id"] == "pro_mensal"


def test_play_purchase_rejects_unknown_product(client, auth):
    resp = client.post(
        "/v1/subscription/play",
        json={"product_id": "outro", "purchase_token": "token123"},
        headers=auth,
    )
    assert resp.status_code == 400


def test_pro_email_gets_lifetime_pro(client, auth, monkeypatch):
    """E-mail na lista PRO_EMAILS recebe Pro sem trial nem compra."""
    from app.config import get_settings

    monkeypatch.setenv("PRO_EMAILS", "a@entreggo.app")
    get_settings.cache_clear()
    try:
        resp = client.get("/v1/subscription", headers=auth)
    finally:
        get_settings.cache_clear()
    assert resp.status_code == 200
    body = resp.json()
    assert body["entitlement"] == "pro"
    assert body["source"] == "owner"
    assert body["expires_at"] is None


def test_weekly_dashboard(client, auth, route_id):
    pkg = client.post(
        f"/v1/routes/{route_id}/scan",
        json={"code": "W1", "lat": -23.55, "lng": -46.63},
        headers=auth,
    ).json()
    client.patch(
        f"/v1/packages/{pkg['id']}/status",
        json={"status": "delivered"},
        headers=auth,
    )
    resp = client.get("/v1/dashboard/weekly", headers=auth)
    assert resp.status_code == 200
    body = resp.json()
    assert len(body["days"]) == 7
    assert body["delivered"] == 1
    assert body["success_rate"] == 1.0
    assert body["days"][-1]["delivered"] == 1

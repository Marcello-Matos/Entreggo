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

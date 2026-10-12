def test_create_and_list_routes(client, auth, route_id):
    routes = client.get("/v1/routes", headers=auth).json()
    assert [r["id"] for r in routes] == [route_id]
    assert routes[0]["status"] == "draft"


def test_scan_rejects_duplicates(client, auth, route_id):
    first = client.post(f"/v1/routes/{route_id}/scan", json={"code": "PKG-1"}, headers=auth)
    again = client.post(f"/v1/routes/{route_id}/scan", json={"code": " PKG-1 "}, headers=auth)
    assert first.status_code == 201
    assert again.status_code == 409


def test_geocode_optimize_and_complete(client, auth, route_id):
    for i, address in enumerate(["Rua A, 1", "Rua B, 2", "Rua Inexistente, 0", "Rua C, 3"]):
        client.post(
            f"/v1/routes/{route_id}/packages",
            json={"tracking_code": f"P{i}", "address_text": address, "city": "São Paulo"},
            headers=auth,
        )

    geo = client.post(f"/v1/routes/{route_id}/geocode", headers=auth).json()
    assert geo == {"geocoded": 3, "not_found": 1, "pending": 0, "start_found": True}

    opt = client.post(f"/v1/routes/{route_id}/optimize", headers=auth)
    assert opt.status_code == 200
    body = opt.json()
    assert [s["sequence"] for s in body["stops"]] == [1, 2, 3]
    assert len(body["skipped_package_ids"]) == 1
    assert body["total_distance_m"] > 0
    assert body["provider"] == "haversine"

    detail = client.get(f"/v1/routes/{route_id}", headers=auth).json()
    assert detail["status"] == "optimized"
    assert len(detail["stops"]) == 3

    for pkg in detail["packages"]:
        new_status = "skipped" if pkg["address_status"] != "ready" else "delivered"
        resp = client.patch(
            f"/v1/packages/{pkg['id']}/status", json={"status": new_status}, headers=auth
        )
        assert resp.status_code == 200

    summary = client.get(f"/v1/routes/{route_id}/summary", headers=auth).json()
    assert summary["status"] == "completed"
    assert summary["by_status"] == {"delivered": 3, "skipped": 1}


def test_scan_confirms_package_from_spreadsheet(client, auth, route_id):
    client.post(
        f"/v1/routes/{route_id}/packages",
        json={"tracking_code": "ML-1", "address_text": "Rua A, 1"},
        headers=auth,
    )
    first = client.post(f"/v1/routes/{route_id}/scan", json={"code": "ML-1"}, headers=auth)
    assert first.status_code == 200
    assert first.json()["address_text"] == "Rua A, 1"
    assert first.json()["scanned_at"] is not None
    again = client.post(f"/v1/routes/{route_id}/scan", json={"code": "ML-1"}, headers=auth)
    assert again.status_code == 409


def test_optimize_uses_gps_start(client, auth):
    rid = client.post("/v1/routes", json={"title": "GPS"}, headers=auth).json()["id"]
    client.post(
        f"/v1/routes/{rid}/packages",
        json={"tracking_code": "X", "lat": -23.56, "lng": -46.65},
        headers=auth,
    )
    resp = client.post(
        f"/v1/routes/{rid}/optimize", json={"start_lat": -23.55, "start_lng": -46.63}, headers=auth
    )
    assert resp.status_code == 200
    assert client.get(f"/v1/routes/{rid}", headers=auth).json()["start_lat"] == -23.55


def test_manual_address_correction(client, auth, other_auth, route_id):
    pkg = client.post(f"/v1/routes/{route_id}/scan", json={"code": "S1"}, headers=auth).json()
    body = {"address_text": "Rua Nova, 10", "city": "São Paulo"}
    url = f"/v1/packages/{pkg['id']}"
    assert client.patch(url, json=body, headers=other_auth).status_code == 404

    updated = client.patch(url, json=body, headers=auth).json()
    assert updated["address_text"] == "Rua Nova, 10"
    assert updated["address_status"] == "pending_review"
    geo = client.post(f"/v1/routes/{route_id}/geocode", headers=auth).json()
    assert geo["geocoded"] == 1


def test_optimize_requires_start_point(client, auth):
    rid = client.post("/v1/routes", json={"title": "Sem início"}, headers=auth).json()["id"]
    assert client.post(f"/v1/routes/{rid}/optimize", headers=auth).status_code == 422


def test_start_address_is_geocoded_on_optimize(client, auth):
    rid = client.post(
        "/v1/routes", json={"title": "Com partida", "start_address": "Praça da Sé"}, headers=auth
    ).json()["id"]
    client.post(
        f"/v1/routes/{rid}/packages",
        json={"tracking_code": "X", "lat": -23.56, "lng": -46.65},
        headers=auth,
    )
    assert client.post(f"/v1/routes/{rid}/optimize", headers=auth).status_code == 200
    route = client.get(f"/v1/routes/{rid}", headers=auth).json()
    assert route["start_lat"] is not None
    assert route["start_address"] == "Praça da Sé"


def test_free_plan_package_limit(client, auth, route_id):
    for i in range(30):
        client.post(f"/v1/routes/{route_id}/scan", json={"code": f"C{i}"}, headers=auth)
    resp = client.post(f"/v1/routes/{route_id}/scan", json={"code": "extra"}, headers=auth)
    assert resp.status_code == 403


def test_default_subscription_is_free(client, auth):
    sub = client.get("/v1/subscription", headers=auth).json()
    assert sub["entitlement"] == "free"
    assert sub["limits"]["max_packages_per_route"] == 30


def test_update_route_title(client, auth, other_auth, route_id):
    url = f"/v1/routes/{route_id}"
    assert client.patch(url, json={"title": "X"}, headers=other_auth).status_code == 404
    resp = client.patch(url, json={"title": "Rota renomeada"}, headers=auth)
    assert resp.status_code == 200
    assert resp.json()["title"] == "Rota renomeada"
    assert client.patch(url, json={"title": ""}, headers=auth).status_code == 422


def test_delete_package(client, auth, other_auth, route_id):
    pkg = client.post(f"/v1/routes/{route_id}/scan", json={"code": "D1"}, headers=auth).json()
    url = f"/v1/packages/{pkg['id']}"
    assert client.delete(url, headers=other_auth).status_code == 404

    assert client.delete(url, headers=auth).status_code == 204
    detail = client.get(f"/v1/routes/{route_id}", headers=auth).json()
    assert detail["packages"] == []

    # código pode ser escaneado de novo depois de excluído
    resp = client.post(f"/v1/routes/{route_id}/scan", json={"code": "D1"}, headers=auth)
    assert resp.status_code == 201


def test_delete_route_removes_everything(client, auth, other_auth, route_id):
    client.post(f"/v1/routes/{route_id}/scan", json={"code": "E1"}, headers=auth)
    client.post(f"/v1/routes/{route_id}/geocode", headers=auth)
    client.post(
        f"/v1/routes/{route_id}/optimize",
        json={"start_lat": -23.55, "start_lng": -46.63},
        headers=auth,
    )
    assert client.delete(f"/v1/routes/{route_id}", headers=other_auth).status_code == 404

    assert client.delete(f"/v1/routes/{route_id}", headers=auth).status_code == 204
    assert client.get(f"/v1/routes/{route_id}", headers=auth).status_code == 404
    assert client.get("/v1/routes", headers=auth).json() == []


def test_dashboard_today(client, auth, other_auth, route_id):
    for code in ("A", "B", "C", "D"):
        client.post(f"/v1/routes/{route_id}/scan", json={"code": code}, headers=auth)
    pkgs = client.get(f"/v1/routes/{route_id}", headers=auth).json()["packages"]
    client.patch(f"/v1/packages/{pkgs[0]['id']}/status", json={"status": "delivered"}, headers=auth)
    client.patch(
        f"/v1/packages/{pkgs[1]['id']}/status", json={"status": "failed_attempt"}, headers=auth
    )

    dash = client.get("/v1/dashboard", headers=auth).json()
    assert (dash["packages"], dash["delivered"], dash["failed"], dash["pending"]) == (4, 1, 1, 2)
    assert dash["progress"] == 0.5
    assert dash["active_route"]["id"] == route_id
    assert dash["active_route"]["remaining"] == 2

    future = client.get("/v1/dashboard", params={"since": "2999-01-01T00:00:00Z"}, headers=auth)
    assert future.json()["packages"] == 0
    assert client.get("/v1/dashboard", headers=other_auth).json()["active_route"] is None

    listed = client.get("/v1/routes", headers=auth).json()[0]
    assert (listed["total_packages"], listed["delivered_packages"]) == (4, 1)

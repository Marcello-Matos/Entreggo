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
    assert geo == {"geocoded": 3, "not_found": 1, "pending": 0}

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


def test_optimize_requires_start_point(client, auth):
    rid = client.post("/v1/routes", json={"title": "Sem início"}, headers=auth).json()["id"]
    assert client.post(f"/v1/routes/{rid}/optimize", headers=auth).status_code == 422


def test_free_plan_package_limit(client, auth, route_id):
    for i in range(30):
        client.post(f"/v1/routes/{route_id}/scan", json={"code": f"C{i}"}, headers=auth)
    resp = client.post(f"/v1/routes/{route_id}/scan", json={"code": "extra"}, headers=auth)
    assert resp.status_code == 403


def test_default_subscription_is_free(client, auth):
    sub = client.get("/v1/subscription", headers=auth).json()
    assert sub["entitlement"] == "free"
    assert sub["limits"]["max_packages_per_route"] == 30

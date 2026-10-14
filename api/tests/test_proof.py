PNG = bytes.fromhex(
    "89504e470d0a1a0a0000000d494844520000000100000001080600000"
    "01f15c4890000000d49444154789c626001000000ffff030000060005"
    "57bfabd40000000049454e44ae426082"
)


def _package(client, auth, route_id) -> dict:
    resp = client.post(f"/v1/routes/{route_id}/scan", json={"code": "CX1"}, headers=auth)
    assert resp.status_code == 201
    return resp.json()


def test_delivery_proof_full(client, auth, route_id):
    pkg = _package(client, auth, route_id)
    url = f"/v1/packages/{pkg['id']}"

    # entrega com recebedor + GPS registrados no ato
    resp = client.patch(
        f"{url}/status",
        json={
            "status": "delivered",
            "recipient_name": "Maria Silva",
            "lat": -23.5505,
            "lng": -46.6333,
        },
        headers=auth,
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["recipient_name"] == "Maria Silva"
    assert body["delivered_at"] is not None
    assert body["has_proof_photo"] is False

    # foto do pacote no local
    resp = client.put(
        f"{url}/photo",
        files={"file": ("entrega.jpg", b"\xff\xd8\xffjpeg", "image/jpeg")},
        headers=auth,
    )
    assert resp.status_code == 204
    got = client.get(f"{url}/photo", headers=auth)
    assert got.status_code == 200
    assert got.content == b"\xff\xd8\xffjpeg"

    detail = client.get(f"/v1/routes/{route_id}", headers=auth).json()
    assert detail["packages"][0]["has_proof_photo"] is True


def test_proof_validations(client, auth, route_id):
    pkg = _package(client, auth, route_id)
    url = f"/v1/packages/{pkg['id']}"
    assert (
        client.put(
            f"{url}/photo",
            files={"file": ("a.txt", b"texto", "text/plain")},
            headers=auth,
        ).status_code
        == 415
    )
    assert client.get(f"{url}/photo", headers=auth).status_code == 404


def test_proof_private_to_owner(client, auth, other_auth, route_id):
    pkg = _package(client, auth, route_id)
    url = f"/v1/packages/{pkg['id']}"
    assert client.get(f"{url}/photo", headers=other_auth).status_code == 404
    assert (
        client.patch(
            f"{url}/status",
            json={"status": "delivered", "recipient_name": "X"},
            headers=other_auth,
        ).status_code
        == 404
    )

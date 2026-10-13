PNG = bytes.fromhex(
    "89504e470d0a1a0a0000000d494844520000000100000001080600000"
    "01f15c4890000000d49444154789c626001000000ffff030000060005"
    "57bfabd40000000049454e44ae426082"
)


def test_photo_upload_get_delete(client, auth):
    url = "/v1/users/me/photo"
    assert client.get(url, headers=auth).status_code == 404

    resp = client.put(
        url,
        files={"file": ("foto.png", PNG, "image/png")},
        headers=auth,
    )
    assert resp.status_code == 204

    got = client.get(url, headers=auth)
    assert got.status_code == 200
    assert got.content == PNG
    assert got.headers["content-type"] == "image/png"

    # substituir mantém uma foto só
    resp = client.put(
        url,
        files={"file": ("foto.png", b"\x89PNG-other", "image/png")},
        headers=auth,
    )
    assert resp.status_code == 204
    assert client.get(url, headers=auth).content == b"\x89PNG-other"

    assert client.delete(url, headers=auth).status_code == 204
    assert client.get(url, headers=auth).status_code == 404


def test_photo_validations(client, auth):
    url = "/v1/users/me/photo"
    resp = client.put(url, files={"file": ("a.txt", b"texto", "text/plain")}, headers=auth)
    assert resp.status_code == 415
    resp = client.put(
        url,
        files={"file": ("big.png", b"\x00" * (5 * 1024 * 1024 + 1), "image/png")},
        headers=auth,
    )
    assert resp.status_code == 413
    assert client.get(url, headers=auth).status_code == 404


def test_photo_detects_type_by_content(client, auth):
    """iPhone envia HEIC e às vezes declara o tipo como octet-stream."""
    url = "/v1/users/me/photo"
    heic = b"\x00\x00\x00\x20ftypheic" + b"\x00" * 8
    resp = client.put(url, files={"file": ("f.heic", heic, "image/heic")}, headers=auth)
    assert resp.status_code == 204
    assert client.get(url, headers=auth).headers["content-type"] == "image/heic"

    resp = client.put(
        url,
        files={"file": ("f.png", PNG, "application/octet-stream")},
        headers=auth,
    )
    assert resp.status_code == 204
    assert client.get(url, headers=auth).headers["content-type"] == "image/png"


def test_photo_requires_auth_and_is_private(client, auth, other_auth):
    url = "/v1/users/me/photo"
    assert client.get(url).status_code == 401
    client.put(url, files={"file": ("f.png", PNG, "image/png")}, headers=auth)
    assert client.get(url, headers=other_auth).status_code == 404

import io
import json

import pytest
from openpyxl import Workbook

from app.services.importer import ImportFileError, parse_import

CSV_SEMICOLON = (
    "Código;Endereço;Cidade;UF;CEP;Obs\n"
    "PKG-1;Rua das Flores, 120;São Paulo;sp;01000000;Portaria B\n"
    "PKG-2;Rua B, 2;São Paulo;SP;123;\n"
    ";;;;;\n"
    "PKG-3;;;;;\n"
    ";;São Paulo;;;sem nada\n"
).encode()


def test_parse_csv_with_semicolon_and_accents():
    parsed = parse_import("lista.csv", CSV_SEMICOLON)
    assert parsed.mapping["address"] == "Endereço"
    assert [r["tracking_code"] for r in parsed.rows] == ["PKG-1", "PKG-2", "PKG-3"]
    assert parsed.rows[0]["postal_code"] == "01000-000"
    assert parsed.rows[0]["state"] == "SP"
    assert parsed.rows[1]["postal_code"] is None
    assert {e["line"] for e in parsed.errors} == {3, 6}


def test_parse_latin1_csv():
    content = 'codigo,endereco\nX1,"Av. São João, 10"\n'.encode("latin-1")
    parsed = parse_import("a.csv", content)
    assert parsed.rows[0]["address"] == "Av. São João, 10"


def test_rejects_fake_extension():
    with pytest.raises(ImportFileError):
        parse_import("lista.xlsx", b"codigo,endereco\n1,rua")


def test_rejects_too_many_rows():
    content = ("codigo\n" + "\n".join(f"C{i}" for i in range(11))).encode()
    with pytest.raises(ImportFileError):
        parse_import("a.csv", content, max_rows=10)


def _xlsx() -> bytes:
    wb = Workbook()
    ws = wb.active
    ws.append(["tracking_code", "address", "postal_code"])
    ws.append(["X1", "Rua A, 1", "01000-000"])
    ws.append(["X2", "Rua B, 2", None])
    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()


def test_import_job_is_idempotent(client, auth, route_id):
    def upload():
        return client.post(
            "/v1/import-jobs",
            data={"route_id": route_id},
            files={"file": ("lista.xlsx", _xlsx())},
            headers=auth,
        ).json()

    first = upload()
    assert first["status"] == "completed"
    assert first["error_summary"]["imported"] == 2

    second = upload()
    assert second["error_summary"]["imported"] == 0
    assert second["error_summary"]["duplicates"] == 2

    job = client.get(f"/v1/import-jobs/{first['id']}", headers=auth)
    assert job.status_code == 200
    assert len(client.get(f"/v1/routes/{route_id}", headers=auth).json()["packages"]) == 2


def test_import_with_custom_mapping(client, auth, route_id):
    content = b'Ref,Local\nR1,"Rua Z, 9"\n'
    job = client.post(
        "/v1/import-jobs",
        data={
            "route_id": route_id,
            "mapping": json.dumps({"tracking_code": "Ref", "address": "Local"}),
        },
        files={"file": ("x.csv", content)},
        headers=auth,
    ).json()
    assert job["error_summary"]["imported"] == 1


def test_import_job_failure_is_recorded(client, auth, route_id):
    job = client.post(
        "/v1/import-jobs",
        data={"route_id": route_id},
        files={"file": ("x.pdf", b"%PDF-1.4")},
        headers=auth,
    ).json()
    assert job["status"] == "failed"
    assert "Formato" in job["error_summary"]["message"]

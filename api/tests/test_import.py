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
    assert "PDF inválido" in job["error_summary"]["message"]


def _pdf_with_lines(*lines: str) -> bytes:
    """PDF mínimo válido: uma página Helvetica com as linhas dadas (sem acentos)."""
    ops = "BT /F1 12 Tf 14 TL 50 750 Td " + " ".join(f"({t}) Tj T*" for t in lines) + " ET"
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
        b"/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
        f"<< /Length {len(ops)} >>\nstream\n{ops}\nendstream".encode(),
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    out = io.BytesIO()
    out.write(b"%PDF-1.4\n")
    offsets = []
    for i, obj in enumerate(objects, 1):
        offsets.append(out.tell())
        out.write(f"{i} 0 obj\n".encode() + obj + b"\nendobj\n")
    xref = out.tell()
    out.write(f"xref\n0 {len(objects) + 1}\n".encode())
    out.write(b"0000000000 65535 f \n")
    for off in offsets:
        out.write(f"{off:010d} 00000 n \n".encode())
    out.write(
        f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF".encode()
    )
    return out.getvalue()


def test_parse_pdf_romaneio():
    pdf = _pdf_with_lines(
        "ROMANEIO DE ENTREGAS",
        "Pedido: MLB998877",
        "Rua Augusta, 1500 - Sao Paulo/SP",
        "CEP: 01304-001",
        "PKG-223344",
        "Av. Paulista, 1578",
        "Sao Paulo - SP",
        "Obs: entregar na portaria",
    )
    parsed = parse_import("romaneio.pdf", pdf)
    assert len(parsed.rows) == 2
    first, second = parsed.rows
    assert first["tracking_code"] == "MLB998877"
    assert first["address"] == "Rua Augusta, 1500"
    assert first["city"] == "Sao Paulo"
    assert first["state"] == "SP"
    assert first["postal_code"] == "01304-001"
    assert second["tracking_code"] == "PKG-223344"
    assert second["address"] == "Av. Paulista, 1578"
    assert second["delivery_notes"] == "entregar na portaria"


def test_parse_pdf_without_addresses():
    pdf = _pdf_with_lines("Relatorio de vendas", "Total: 42 itens")
    with pytest.raises(ImportFileError):
        parse_import("relatorio.pdf", pdf)


def test_parse_pdf_rejects_column_mapping():
    pdf = _pdf_with_lines("Rua A, 1")
    with pytest.raises(ImportFileError):
        parse_import("x.pdf", pdf, mapping={"address": "Endereço"})


def test_parse_pdf_numbered_table_keeps_each_cep_with_its_address():
    # Layout real: "Nº / Logradouro — bairro, cidade/UF / CEP", com travessão.
    from app.services.importer import parse_pdf_lines

    lines = ["Nº", "Logradouro / município", "CEP"]
    expected = []
    for n in range(1, 31):
        lines += [str(n), f"Rua Teste {n}, {n * 10} — Centro, Osasco/SP", f"06{n:03d}-000"]
        expected.append((f"Rua Teste {n}, {n * 10} - Centro", f"06{n:03d}-000"))
    rows = parse_pdf_lines(lines)
    assert [(r["address"], r["postal_code"]) for r in rows] == expected
    assert all(r["city"] == "Osasco" and r["state"] == "SP" for r in rows)
    assert all(r.get("tracking_code") is None for r in rows)


@pytest.mark.parametrize(
    "lines",
    [
        ["1", "Rua Anastacia Jachimov, 136 — Osasco/SP", "06290-180"],
        ["Rua Anastacia Jachimov, 136 - Osasco/SP - 06290-180"],
        ["1. Rua Anastacia Jachimov, 136 - Osasco/SP", "CEP 06290-180"],
        ["1 Rua Anastacia Jachimov, 136 Osasco SP 06290-180"],
        ["Endereço: Rua Anastacia Jachimov, 136", "Osasco - SP", "06290-180"],
        ["Rua Anastacia Jachimov, 136 - Centro - Osasco - SP", "06290-180"],
        ["Rua Anastacia Jachimov, 136, Centro, Osasco, SP, 06290-180"],
        ["Rua Anastacia Jachimov, 136 - Osasco/SP", "CEP: 06290180"],
        ["MLB123456789 Rua Anastacia Jachimov, 136 - Osasco/SP 06290-180"],
        ["R. ANASTACIA JACHIMOV, 136 - OSASCO/SP", "06290-180"],
        ["Rua Anastacia Jachimov; 136; Centro; Osasco; SP; 06290-180"],
    ],
    ids=[
        "travessao",
        "cep-mesma-linha",
        "numero-lista",
        "linha-tabela",
        "rotulo-endereco",
        "cidade-hifen",
        "cidade-virgula",
        "cep-sem-hifen",
        "codigo-na-frente",
        "abreviado-caixa-alta",
        "ponto-e-virgula",
    ],
)
def test_pdf_address_formats(lines):
    from app.services.importer import normalize_postal_code, parse_pdf_lines

    (row,) = parse_pdf_lines(lines)
    assert row["address"].lower().startswith(("rua anastacia jachimov, 136", "r. anastacia"))
    assert (row["city"], row["state"]) == ("Osasco", "SP")
    assert normalize_postal_code(row["postal_code"]) == "06290-180"


def test_csv_full_address_in_one_cell():
    content = b"codigo;endereco\nA1;AV. PAULISTA, 1578, SAO PAULO, SP, 01310200\n"
    (row,) = parse_import("a.csv", content).rows
    assert row["address"] == "Av. Paulista, 1578"
    assert (row["city"], row["state"], row["postal_code"]) == ("Sao Paulo", "SP", "01310-200")

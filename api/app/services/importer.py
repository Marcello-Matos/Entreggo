import csv
import io
import re
import unicodedata
from dataclasses import dataclass, field

from openpyxl import load_workbook

FIELDS = (
    "tracking_code",
    "address",
    "city",
    "state",
    "postal_code",
    "recipient_reference",
    "delivery_notes",
)

ALIASES = {
    "tracking_code": {"tracking_code", "codigo", "cod", "rastreio", "tracking", "pedido", "pacote"},
    "address": {"address", "endereco", "logradouro", "rua", "endereco_completo"},
    "city": {"city", "cidade", "municipio"},
    "state": {"state", "uf", "estado"},
    "postal_code": {"postal_code", "cep", "codigo_postal"},
    "recipient_reference": {"recipient_reference", "destinatario", "cliente", "referencia"},
    "delivery_notes": {"delivery_notes", "observacao", "observacoes", "obs", "notas"},
}

XLSX_MAGIC = b"PK\x03\x04"


class ImportFileError(ValueError):
    pass


@dataclass
class ParsedImport:
    rows: list[dict[str, str | None]] = field(default_factory=list)
    errors: list[dict] = field(default_factory=list)
    mapping: dict[str, str] = field(default_factory=dict)


def normalize_header(value: str) -> str:
    text = unicodedata.normalize("NFKD", str(value)).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "_", text.strip().lower()).strip("_")


def normalize_postal_code(value: str) -> str | None:
    digits = re.sub(r"\D", "", value)
    return f"{digits[:5]}-{digits[5:]}" if len(digits) == 8 else None


def _read_table(filename: str, content: bytes) -> list[list[str]]:
    is_zip = content.startswith(XLSX_MAGIC)
    ext = filename.lower().rsplit(".", 1)[-1] if "." in filename else ""
    if ext == "xlsx" and is_zip:
        sheet = load_workbook(io.BytesIO(content), read_only=True, data_only=True).active
        return [
            ["" if cell is None else str(cell).strip() for cell in row]
            for row in sheet.iter_rows(values_only=True)
        ]
    if ext in ("csv", "txt") and not is_zip and b"\x00" not in content[:4096]:
        try:
            text = content.decode("utf-8-sig")
        except UnicodeDecodeError:
            text = content.decode("latin-1")
        try:
            dialect = csv.Sniffer().sniff(text[:4096], delimiters=",;\t|")
        except csv.Error:
            dialect = csv.excel
        return [[c.strip() for c in row] for row in csv.reader(io.StringIO(text), dialect)]
    raise ImportFileError("Formato não suportado: envie um arquivo CSV ou XLSX válido")


def detect_mapping(headers: list[str]) -> dict[str, str]:
    """Mapeia campo do Entreggo -> cabeçalho original da planilha."""
    mapping = {}
    for header in headers:
        norm = normalize_header(header)
        for field_name, aliases in ALIASES.items():
            if norm in aliases and field_name not in mapping:
                mapping[field_name] = header
    return mapping


def parse_import(
    filename: str, content: bytes, mapping: dict[str, str] | None = None, max_rows: int = 2000
) -> ParsedImport:
    table = [(n, row) for n, row in enumerate(_read_table(filename, content), 1) if any(row)]
    if not table:
        raise ImportFileError("Arquivo vazio")
    headers, data = table[0][1], table[1:]
    if len(data) > max_rows:
        raise ImportFileError(f"Limite de {max_rows} linhas excedido ({len(data)} linhas)")

    mapping = mapping or detect_mapping(headers)
    unknown = {k for k in mapping if k not in FIELDS} | {
        v for v in mapping.values() if v not in headers
    }
    if unknown:
        raise ImportFileError(f"Mapeamento inválido: {sorted(unknown)}")
    if "tracking_code" not in mapping and "address" not in mapping:
        raise ImportFileError("Nenhuma coluna de código ou endereço reconhecida")

    index = {f: headers.index(h) for f, h in mapping.items()}
    result = ParsedImport(mapping=mapping)
    for line_no, raw in data:
        row = {f: (raw[i].strip() or None) if i < len(raw) else None for f, i in index.items()}
        if not row.get("tracking_code") and not row.get("address"):
            result.errors.append({"line": line_no, "message": "Linha sem código e sem endereço"})
            continue
        if row.get("postal_code"):
            cep = normalize_postal_code(row["postal_code"])
            if cep is None:
                result.errors.append({"line": line_no, "message": "CEP inválido; campo ignorado"})
            row["postal_code"] = cep
        if row.get("state"):
            row["state"] = row["state"].upper()[:2]
        result.rows.append(row)
    return result

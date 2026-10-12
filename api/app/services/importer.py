import csv
import io
import re
import unicodedata
from dataclasses import dataclass, field

from openpyxl import load_workbook
from pypdf import PdfReader

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
PDF_MAGIC = b"%PDF"

# Padrões de romaneio/lista de entrega em PDF (texto livre, sem colunas garantidas).
_STREET = re.compile(
    r"^(?:rua|r\.|avenida|av\.?|estrada|estr\.|rodovia|rod\.?|travessa|trav\.?|tv\.|"
    r"alameda|al\.?|pra[cç]a|p[cç]a\.?|largo|lgo\.?|beco|bc\.|quadra|qd\.?|viela|vl\.|"
    r"caminho|boulevard|blvd\.?|setor|loteamento|condom[ií]nio)\b[\s.,]",
    re.IGNORECASE,
)
_CEP = re.compile(r"\bcep\b[:\s.\-]*(\d{5}-?\d{3})|\b(\d{5}-\d{3})\b", re.IGNORECASE)
_CITY_UF_TAIL = re.compile(r"[-–,]\s*([A-Za-zÀ-ÖØ-öø-ÿ' ]{2,}?)\s*/\s*([A-Z]{2})\s*$")
_CITY_UF_LINE = re.compile(r"^([A-Za-zÀ-ÖØ-öø-ÿ' .]{2,}?)\s*[-/]\s*([A-Z]{2})$")
_LABELED_CODE = re.compile(
    r"(?:pedido|pacote|c[oó]d(?:igo)?\.?|rastreio|tracking|ordem)\b"
    r"\s*[:#nºo°.\-]*\s*([A-Z0-9][\w\-]{5,})",
    re.IGNORECASE,
)
_BARE_CODE = re.compile(r"^(?=.{8,}$)[A-Z0-9][A-Z0-9\-]*\d[A-Z0-9\-]*$", re.IGNORECASE)
_NOTE = re.compile(r"^obs(?:erva[çc][ãa]o)?\.?\s*[:.\-]?\s*(.+)", re.IGNORECASE)


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
    raise ImportFileError("Formato não suportado: envie um arquivo CSV, XLSX ou PDF válido")


def parse_pdf_lines(lines: list[str]) -> list[dict[str, str | None]]:
    """Extrai registros de um romaneio em texto: cada linha de logradouro inicia um
    registro e as linhas vizinhas (até 4 para cada lado) fornecem CEP, cidade/UF,
    código de rastreio e observação."""
    used: set[int] = set()
    records: list[dict[str, str | None]] = []
    for i, line in enumerate(lines):
        if i in used or not _STREET.match(line):
            continue
        used.add(i)
        rec: dict[str, str | None] = {"address": line}
        tail = _CITY_UF_TAIL.search(line)
        if tail:
            rec["address"] = line[: tail.start()].rstrip(" ,-–")
            rec["city"], rec["state"] = tail.group(1).strip(), tail.group(2)
        for j in range(max(0, i - 4), min(len(lines), i + 5)):
            if j == i or j in used:
                continue
            near = lines[j]
            cep = _CEP.search(near)
            if cep and rec.get("postal_code") is None:
                rec["postal_code"] = cep.group(1) or cep.group(2)
                used.add(j)
                continue
            labeled = _LABELED_CODE.search(near)
            if labeled and rec.get("tracking_code") is None:
                rec["tracking_code"] = labeled.group(1)
                used.add(j)
                continue
            city = _CITY_UF_LINE.match(near)
            if city and rec.get("city") is None:
                rec["city"], rec["state"] = city.group(1).strip(), city.group(2)
                used.add(j)
                continue
            if rec.get("tracking_code") is None and _BARE_CODE.match(near):
                rec["tracking_code"] = near
                used.add(j)
                continue
            note = _NOTE.match(near)
            if note and rec.get("delivery_notes") is None:
                rec["delivery_notes"] = note.group(1).strip()
                used.add(j)
        records.append(rec)
    return records


def _parse_pdf(content: bytes, max_rows: int) -> ParsedImport:
    try:
        reader = PdfReader(io.BytesIO(content))
        lines = [
            line.strip()
            for page in reader.pages
            for line in (page.extract_text() or "").splitlines()
            if line.strip()
        ]
    except ImportFileError:
        raise
    except Exception as exc:
        raise ImportFileError("PDF inválido ou protegido por senha") from exc
    if not lines:
        raise ImportFileError(
            "PDF sem texto legível — pode ser um documento digitalizado como imagem"
        )
    records = parse_pdf_lines(lines)
    if len(records) > max_rows:
        raise ImportFileError(f"Limite de {max_rows} linhas excedido ({len(records)} endereços)")
    result = ParsedImport(mapping={"source": "pdf"})
    for rec in records:
        if rec.get("postal_code"):
            rec["postal_code"] = normalize_postal_code(rec["postal_code"])
        if rec.get("state"):
            rec["state"] = rec["state"].upper()[:2]
        result.rows.append({f: rec.get(f) for f in FIELDS})
    if not result.rows:
        raise ImportFileError("Nenhum endereço reconhecido no PDF")
    return result


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
    if content.startswith(PDF_MAGIC):
        if mapping:
            raise ImportFileError("Mapeamento de colunas não se aplica a PDF")
        return _parse_pdf(content, max_rows)
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

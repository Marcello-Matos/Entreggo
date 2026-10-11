import json
import uuid

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.config import Settings, get_settings
from app.db import get_db
from app.deps import ensure_capacity, get_owned_route, mark_route_changed, plan_limits
from app.models import ImportJob, Package, User
from app.schemas import ImportJobOut
from app.services.importer import ImportFileError, normalize_header, parse_import

router = APIRouter(prefix="/v1/import-jobs", tags=["import"])


def _dedupe_key(code: str | None, address: str | None, postal_code: str | None) -> tuple:
    if code:
        return ("code", code.strip())
    return ("addr", normalize_header(address or ""), postal_code or "")


@router.post("", response_model=ImportJobOut, status_code=status.HTTP_201_CREATED)
async def create_import_job(
    route_id: uuid.UUID = Form(...),
    mapping: str | None = Form(default=None, description='JSON: {"address": "Endereço", ...}'),
    file: UploadFile = File(...),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
):
    route = get_owned_route(db, route_id, user)
    content = await file.read(settings.max_import_bytes + 1)
    if len(content) > settings.max_import_bytes:
        raise HTTPException(status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, "Arquivo muito grande")
    try:
        column_map = json.loads(mapping) if mapping else None
    except json.JSONDecodeError as exc:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Mapeamento inválido") from exc

    filename = (file.filename or "arquivo")[:255]
    job = ImportJob(user_id=user.id, route_id=route.id, filename=filename)
    db.add(job)
    _, limits = plan_limits(db, user)
    try:
        parsed = parse_import(
            filename,
            content,
            column_map,
            max_rows=min(settings.max_import_rows, limits["max_import_rows"]),
        )
    except ImportFileError as exc:
        job.status, job.error_summary = "failed", {"message": str(exc)}
        db.commit()
        return job

    seen = {_dedupe_key(p.tracking_code, p.address_text, p.postal_code) for p in route.packages}
    new_packages, duplicates = [], 0
    for row in parsed.rows:
        key = _dedupe_key(row.get("tracking_code"), row.get("address"), row.get("postal_code"))
        if key in seen:
            duplicates += 1
            continue
        seen.add(key)
        new_packages.append(
            Package(
                route_id=route.id,
                tracking_code=row.get("tracking_code"),
                address_text=row.get("address"),
                city=row.get("city"),
                state=row.get("state"),
                postal_code=row.get("postal_code"),
                recipient_reference=row.get("recipient_reference"),
                delivery_notes=row.get("delivery_notes"),
            )
        )

    ensure_capacity(db, user, route, len(new_packages))
    db.add_all(new_packages)
    if new_packages:
        mark_route_changed(route)
    job.status = "completed"
    job.error_summary = {
        "mapping": parsed.mapping,
        "imported": len(new_packages),
        "duplicates": duplicates,
        "missing_address": sum(1 for p in new_packages if not p.address_text),
        "errors": parsed.errors,
    }
    db.commit()
    return job


@router.get("/{job_id}", response_model=ImportJobOut)
def get_import_job(
    job_id: uuid.UUID, user: User = Depends(get_current_user), db: Session = Depends(get_db)
):
    job = db.get(ImportJob, job_id)
    if job is None or job.user_id != user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Importação não encontrada")
    return job

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.db import get_db
from app.models import DeliveryEvent, Package, User
from app.schemas import PackageOut, StatusUpdate

router = APIRouter(prefix="/v1/packages", tags=["packages"])


@router.patch("/{package_id}/status", response_model=PackageOut)
def update_status(
    package_id: uuid.UUID,
    body: StatusUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    pkg = db.get(Package, package_id)
    if pkg is None or pkg.route.user_id != user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Pacote não encontrado")

    pkg.status = body.status
    db.add(DeliveryEvent(package_id=pkg.id, event_type=f"status:{body.status}", note=body.note))
    route = pkg.route
    if all(p.status != "pending" for p in route.packages):
        route.status = "completed"
    elif body.status != "pending" and route.status in ("optimized", "validated", "draft"):
        route.status = "in_progress"
    db.commit()
    return pkg

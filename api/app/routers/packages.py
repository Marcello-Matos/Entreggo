import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import delete, select
from sqlalchemy.orm import Session, joinedload

from app.auth import get_current_user
from app.db import get_db
from app.deps import mark_route_changed
from app.models import DeliveryEvent, Package, Route, RouteStop, User
from app.schemas import PackageOut, PackageUpdate, StatusUpdate

router = APIRouter(prefix="/v1/packages", tags=["packages"])


def _get_owned_package(db: Session, package_id: uuid.UUID, user: User) -> Package:
    pkg = db.scalar(
        select(Package)
        .where(Package.id == package_id)
        .options(joinedload(Package.route).selectinload(Route.packages))
    )
    if pkg is None or pkg.route.user_id != user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Pacote não encontrado")
    return pkg


@router.patch("/{package_id}", response_model=PackageOut)
def update_package(
    package_id: uuid.UUID,
    body: PackageUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Correção manual de endereço: invalida as coordenadas para nova geocodificação."""
    pkg = _get_owned_package(db, package_id, user)
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(pkg, field, value)
    pkg.lat = pkg.lng = pkg.geocode_meta = None
    pkg.address_status = "pending_review"
    mark_route_changed(pkg.route)
    db.commit()
    return pkg


@router.patch("/{package_id}/status", response_model=PackageOut)
def update_status(
    package_id: uuid.UUID,
    body: StatusUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    pkg = _get_owned_package(db, package_id, user)
    pkg.status = body.status
    db.add(DeliveryEvent(package_id=pkg.id, event_type=f"status:{body.status}", note=body.note))
    route = pkg.route
    if all(p.status != "pending" for p in route.packages):
        route.status = "completed"
    elif body.status != "pending" and route.status in ("optimized", "validated", "draft"):
        route.status = "in_progress"
    db.commit()
    return pkg


@router.delete("/{package_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_package(
    package_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Remove o pacote da rota (junto com paradas e eventos associados)."""
    pkg = _get_owned_package(db, package_id, user)
    route = pkg.route
    db.execute(delete(DeliveryEvent).where(DeliveryEvent.package_id == pkg.id))
    db.execute(delete(RouteStop).where(RouteStop.package_id == pkg.id))
    # remove da coleção carregada: o cascade delete-orphan apaga a linha;
    # db.delete() direto a ressuscitaria porque ela segue na coleção
    route.packages.remove(pkg)
    mark_route_changed(route)
    db.commit()

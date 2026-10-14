import uuid

from fastapi import (
    APIRouter,
    Depends,
    File,
    HTTPException,
    Response,
    UploadFile,
    status,
)
from sqlalchemy import delete, select
from sqlalchemy.orm import Session, joinedload

from app.auth import get_current_user
from app.db import get_db
from app.deps import mark_route_changed
from app.models import DeliveryEvent, DeliveryProof, Package, Route, RouteStop, User
from app.schemas import LocationUpdate, PackageOut, PackageUpdate, StatusUpdate
from app.services.images import detect_image_type

MAX_PROOF_PHOTO_BYTES = 5 * 1024 * 1024

router = APIRouter(prefix="/v1/packages", tags=["packages"])


def _get_owned_package(db: Session, package_id: uuid.UUID, user: User) -> Package:
    pkg = db.scalar(
        select(Package)
        .where(Package.id == package_id)
        .options(
            joinedload(Package.route).selectinload(Route.packages),
            joinedload(Package.proof),
        )
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
    if body.status != "pending" and (
        body.recipient_name or body.lat is not None or body.lng is not None
    ):
        # Comprovante: recebedor e/ou posição registrados no ato da entrega.
        proof = pkg.proof or DeliveryProof(package_id=pkg.id)
        pkg.proof = proof
        proof.recipient_name = body.recipient_name or proof.recipient_name
        proof.lat = body.lat if body.lat is not None else proof.lat
        proof.lng = body.lng if body.lng is not None else proof.lng
        db.add(proof)
    route = pkg.route
    if all(p.status != "pending" for p in route.packages):
        route.status = "completed"
    elif body.status != "pending" and route.status in (
        "optimized",
        "validated",
        "draft",
    ):
        route.status = "in_progress"
    db.commit()
    return pkg


@router.patch("/{package_id}/location", response_model=PackageOut)
def update_location(
    package_id: uuid.UUID,
    body: LocationUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Posição física do pacote no veículo (ex.: "Fundo • Meio • Prateleira")."""
    pkg = _get_owned_package(db, package_id, user)
    pkg.vehicle_location = (body.location or "").strip() or None
    db.commit()
    return pkg


@router.put("/{package_id}/photo", status_code=status.HTTP_204_NO_CONTENT)
async def upload_delivery_photo(
    package_id: uuid.UUID,
    file: UploadFile = File(...),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Foto do pacote no local (comprovante de entrega ou de tentativa)."""
    pkg = _get_owned_package(db, package_id, user)
    content = await file.read(MAX_PROOF_PHOTO_BYTES + 1)
    if len(content) > MAX_PROOF_PHOTO_BYTES:
        raise HTTPException(
            status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, "Foto muito grande (máx. 5 MB)"
        )
    media_type = detect_image_type(content)
    if media_type is None and (file.content_type or "").startswith("image/"):
        media_type = file.content_type
    if media_type is None:
        raise HTTPException(status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, "Envie um arquivo de imagem")
    proof = pkg.proof or DeliveryProof(package_id=pkg.id)
    pkg.proof = proof
    proof.photo, proof.photo_content_type = content, media_type
    db.add(proof)
    db.commit()


@router.get("/{package_id}/photo")
def get_delivery_photo(
    package_id: uuid.UUID, user: User = Depends(get_current_user), db: Session = Depends(get_db)
):
    pkg = _get_owned_package(db, package_id, user)
    if pkg.proof is None or not pkg.proof.photo:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Sem foto de entrega")
    return Response(
        content=pkg.proof.photo,
        media_type=pkg.proof.photo_content_type,
        headers={"Cache-Control": "private, max-age=300"},
    )


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

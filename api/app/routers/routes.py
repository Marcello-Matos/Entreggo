import re
import uuid
from collections import Counter
from datetime import UTC, datetime, timedelta

import httpx
from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import delete, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.config import Settings, get_settings
from app.db import get_db
from app.deps import ensure_capacity, get_owned_route, mark_route_changed
from app.models import (
    DeliveryEvent,
    ImportJob,
    Package,
    Route,
    RouteStop,
    User,
    utcnow,
)
from app.schemas import (
    GeocodeResult,
    OptimizeIn,
    OptimizeOut,
    PackageCreate,
    PackageOut,
    RouteCreate,
    RouteDetail,
    RouteOut,
    RouteSummary,
    RouteUpdate,
    ScanIn,
    StopOut,
)
from app.services.geocoding import GeocodeHit, Geocoder, full_address, get_geocoder
from app.services.optimizer import NoSolutionError, haversine_m, optimize_order

router = APIRouter(prefix="/v1/routes", tags=["routes"])

DISCLAIMER = (
    "Sequência estimada por distância em linha reta. Trânsito, restrições de via e acesso "
    "podem alterar o resultado; recalcule quando necessário."
)


@router.post("", response_model=RouteOut, status_code=status.HTTP_201_CREATED)
def create_route(
    body: RouteCreate, user: User = Depends(get_current_user), db: Session = Depends(get_db)
):
    route = Route(user_id=user.id, **body.model_dump())
    db.add(route)
    db.commit()
    return route


@router.get("", response_model=list[RouteOut])
def list_routes(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return db.scalars(
        select(Route).where(Route.user_id == user.id).order_by(Route.created_at.desc())
    ).all()


@router.get("/{route_id}", response_model=RouteDetail)
def get_route(
    route_id: uuid.UUID, user: User = Depends(get_current_user), db: Session = Depends(get_db)
):
    return get_owned_route(db, route_id, user)


@router.patch("/{route_id}", response_model=RouteOut)
def update_route(
    route_id: uuid.UUID,
    body: RouteUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    route = get_owned_route(db, route_id, user)
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(route, field, value)
    db.commit()
    return route


@router.delete("/{route_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_route(
    route_id: uuid.UUID, user: User = Depends(get_current_user), db: Session = Depends(get_db)
):
    """Exclui a rota e tudo que depende dela (pacotes, paradas, eventos, importações)."""
    route = get_owned_route(db, route_id, user)
    package_ids = [p.id for p in route.packages]
    if package_ids:
        db.execute(delete(DeliveryEvent).where(DeliveryEvent.package_id.in_(package_ids)))
    db.execute(delete(ImportJob).where(ImportJob.route_id == route.id))
    db.delete(route)  # cascade ORM remove pacotes e paradas
    db.commit()


def _add_package(db: Session, user: User, route: Route, data: PackageCreate) -> Package:
    ensure_capacity(db, user, route, 1)
    pkg = Package(route_id=route.id, **data.model_dump())
    if pkg.lat is not None and pkg.lng is not None:
        pkg.address_status = "ready"
    db.add(pkg)
    mark_route_changed(route)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(status.HTTP_409_CONFLICT, "Código já cadastrado nesta rota") from exc
    return pkg


@router.post("/{route_id}/packages", response_model=PackageOut, status_code=201)
def add_package(
    route_id: uuid.UUID,
    body: PackageCreate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return _add_package(db, user, get_owned_route(db, route_id, user), body)


@router.post("/{route_id}/scan", response_model=PackageOut, status_code=201)
def scan_package(
    route_id: uuid.UUID,
    body: ScanIn,
    response: Response,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Registra a leitura. Se o código veio de planilha importada, confirma o pacote (200)."""
    route = get_owned_route(db, route_id, user)
    code = body.code.strip()
    existing = db.scalar(
        select(Package).where(Package.route_id == route.id, Package.tracking_code == code)
    )
    if existing is not None:
        if existing.scanned_at is not None:
            raise HTTPException(status.HTTP_409_CONFLICT, "Código já cadastrado nesta rota")
        existing.scanned_at = utcnow()
        db.commit()
        response.status_code = status.HTTP_200_OK
        return existing
    pkg = _add_package(db, user, route, PackageCreate(tracking_code=code))
    pkg.scanned_at = utcnow()
    db.commit()
    return pkg


def _street_part(address: str) -> str:
    """'Rua X, 300 - Bairro, Cidade - UF' -> 'Rua X, 300'."""
    return re.split(r"\s+[-–—]\s+", address, maxsplit=1)[0].strip(" ,")


def _geocode_with_fallback(geocoder: Geocoder, pkg: Package) -> GeocodeHit | None:
    """Tenta o endereço completo e, se falhar, variações mais simples
    (logradouro + cidade/UF, logradouro + CEP, logradouro sem número) e, por
    último, a coordenada do trecho de rua pelo CEP."""
    candidates = [full_address(pkg.address_text, pkg.city, pkg.state, pkg.postal_code)]
    street = _street_part(pkg.address_text or "")
    if street != (pkg.address_text or "").strip():
        candidates.append(full_address(street, pkg.city, pkg.state))
    if pkg.postal_code:
        candidates.append(full_address(street, pkg.city, pkg.postal_code))
    street_name = re.sub(r",\s*(?:\d+\w?|s/?n)\b.*$", "", street, flags=re.IGNORECASE)
    if street_name != street:
        candidates.append(full_address(street_name, pkg.city, pkg.state))
    for query in dict.fromkeys(candidates):
        try:
            hit = geocoder.geocode(query)
        except httpx.HTTPError:
            break  # serviço principal indisponível: segue para os alternativos
        if hit is not None:
            return hit
    structured = getattr(geocoder, "geocode_structured", None)
    if structured is not None:
        hit = structured(street, pkg.city, pkg.state, pkg.postal_code)
        if hit is not None:
            return hit
    cep_fallback = getattr(geocoder, "geocode_cep", None)
    if pkg.postal_code and cep_fallback is not None:
        return cep_fallback(pkg.postal_code)
    return None


def _resolve_start(route: Route, geocoder: Geocoder) -> bool:
    if route.start_lat is not None and route.start_lng is not None:
        return True
    if not route.start_address:
        return False
    try:
        hit = geocoder.geocode(full_address(route.start_address))
    except httpx.HTTPError:
        return False
    if hit is not None:
        route.start_lat, route.start_lng = hit.lat, hit.lng
    return hit is not None


@router.post("/{route_id}/geocode", response_model=GeocodeResult)
def geocode_route(
    route_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
    geocoder: Geocoder = Depends(get_geocoder),
):
    route = get_owned_route(db, route_id, user)
    start_found = _resolve_start(route, geocoder)
    for pkg in route.packages:
        if pkg.address_status == "ready" or not pkg.address_text:
            continue
        try:
            hit = _geocode_with_fallback(geocoder, pkg)
        except httpx.HTTPError:
            continue  # falha pontual: fica pendente, sem interromper os demais
        if hit is None:
            pkg.address_status = "not_found"
            continue
        pkg.lat, pkg.lng, pkg.address_status = hit.lat, hit.lng, "ready"
        pkg.geocode_meta = {
            "provider": hit.provider,
            "confidence": hit.confidence,
            "queried_at": hit.queried_at,
        }

    counts = Counter(p.address_status for p in route.packages)
    if route.packages and counts["ready"] == len(route.packages) and route.status == "draft":
        route.status = "validated"
    db.commit()
    return GeocodeResult(
        geocoded=counts["ready"],
        not_found=counts["not_found"],
        pending=counts["pending_review"],
        start_found=start_found,
    )


@router.post("/{route_id}/optimize", response_model=OptimizeOut)
def optimize_route(
    route_id: uuid.UUID,
    body: OptimizeIn | None = None,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
    geocoder: Geocoder = Depends(get_geocoder),
):
    route = get_owned_route(db, route_id, user)
    if body is not None and body.start_lat is not None and body.start_lng is not None:
        route.start_lat, route.start_lng = body.start_lat, body.start_lng
    elif body is not None and body.start_address:
        route.start_address, route.start_lat, route.start_lng = body.start_address, None, None
    if not _resolve_start(route, geocoder):
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT,
            "Defina um endereço de partida válido para a rota",
        )

    usable = [
        p
        for p in route.packages
        if p.lat is not None and p.lng is not None and p.status == "pending"
    ]
    skipped = [p.id for p in route.packages if p.status == "pending" and p not in usable]
    if not usable:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT, "Nenhum pacote pendente com endereço validado"
        )

    start = (route.start_lat, route.start_lng)
    try:
        result = optimize_order(
            start, [(p.lat, p.lng) for p in usable], settings.optimizer_time_limit_s
        )
    except NoSolutionError as exc:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, str(exc)) from exc

    speed_ms = settings.average_speed_kmh * 1000 / 3600
    clock = route.planned_at or datetime.now(UTC)
    elapsed, prev = 0.0, start
    route.stops.clear()
    db.flush()
    for seq, idx in enumerate(result.order, start=1):
        pkg = usable[idx]
        elapsed += haversine_m(prev, (pkg.lat, pkg.lng)) / speed_ms
        prev = (pkg.lat, pkg.lng)
        route.stops.append(
            RouteStop(
                package_id=pkg.id, sequence=seq, eta_estimate=clock + timedelta(seconds=elapsed)
            )
        )

    route.status = "optimized"
    route.optimization = {
        "provider": "haversine",
        "objective": "distance",
        "total_distance_m": result.total_distance_m,
        "estimated_duration_s": round(elapsed),
        "computed_at": datetime.now(UTC).isoformat(),
        "version": 1 + ((route.optimization or {}).get("version") or 0),
    }
    db.commit()
    return OptimizeOut(
        stops=[StopOut.model_validate(s) for s in route.stops],
        total_distance_m=result.total_distance_m,
        estimated_duration_s=round(elapsed),
        skipped_package_ids=skipped,
        provider="haversine",
        objective="distance",
        disclaimer=DISCLAIMER,
    )


@router.get("/{route_id}/summary", response_model=RouteSummary)
def route_summary(
    route_id: uuid.UUID, user: User = Depends(get_current_user), db: Session = Depends(get_db)
):
    route = get_owned_route(db, route_id, user)
    return RouteSummary(
        route_id=route.id,
        status=route.status,
        total=len(route.packages),
        by_status=dict(Counter(p.status for p in route.packages)),
        pending_address_review=sum(p.address_status != "ready" for p in route.packages),
        total_distance_m=(route.optimization or {}).get("total_distance_m"),
    )

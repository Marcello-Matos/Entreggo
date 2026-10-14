from collections import Counter
from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.auth import get_current_user
from app.db import get_db
from app.models import Package, Route, User
from app.schemas import ActiveRoute, DashboardOut

router = APIRouter(prefix="/v1/dashboard", tags=["dashboard"])


@router.get("", response_model=DashboardOut)
def dashboard(
    since: datetime | None = Query(
        default=None, description="Início do dia no fuso do aparelho (ISO 8601)"
    ),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Resumo do dia: pacotes das rotas criadas desde `since` e a rota em andamento."""
    since = since or datetime.now(UTC) - timedelta(hours=24)
    if since.tzinfo is None:
        since = since.replace(tzinfo=UTC)
    routes = db.scalars(
        select(Route)
        .where(Route.user_id == user.id, Route.created_at >= since)
        .order_by(Route.created_at.desc())
        .options(
            selectinload(Route.packages).joinedload(Package.proof),
            selectinload(Route.stops),
        )
    ).all()
    counts = Counter(p.status for r in routes for p in r.packages)
    total = sum(counts.values())
    done = total - counts["pending"]
    active = next((r for r in routes if r.pending_packages), None)
    next_address = next_eta = None
    next_lat = next_lng = None
    remaining_seconds = None
    if active and active.stops:
        by_id = {p.id: p for p in active.packages}
        pending_stops = sorted(
            (s for s in active.stops if by_id[s.package_id].status == "pending"),
            key=lambda s: s.sequence,
        )
        if pending_stops:
            next_pkg = by_id[pending_stops[0].package_id]
            next_address = next_pkg.address_text
            next_eta = pending_stops[0].eta_estimate
            next_lat, next_lng = next_pkg.lat, next_pkg.lng
            etas = [s.eta_estimate for s in active.stops if s.eta_estimate]
            if etas and next_eta:
                remaining_seconds = max(0, round((max(etas) - next_eta).total_seconds()))
    return DashboardOut(
        packages=total,
        delivered=counts["delivered"],
        failed=counts["failed_attempt"],
        skipped=counts["skipped"],
        pending=counts["pending"],
        progress=round(done / total, 4) if total else 0.0,
        active_route=ActiveRoute(
            id=active.id,
            title=active.title,
            remaining=active.pending_packages,
            optimized=bool(active.stops),
            next_address=next_address,
            next_eta=next_eta,
            next_lat=next_lat,
            next_lng=next_lng,
            remaining_seconds=remaining_seconds,
        )
        if active
        else None,
    )

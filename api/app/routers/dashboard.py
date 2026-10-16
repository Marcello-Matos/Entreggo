from collections import Counter
from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.auth import get_current_user
from app.db import get_db
from app.models import DeliveryEvent, Package, Route, User
from app.schemas import ActiveRoute, DashboardOut, WeeklyDay, WeeklyOut

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


@router.get("/weekly", response_model=WeeklyOut)
def weekly(
    tz_offset_minutes: int = Query(
        default=-180, description="Fuso do aparelho em minutos (UTC-3 = -180)"
    ),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Entregas por dia dos últimos 7 dias, no fuso do aparelho."""
    offset = timedelta(minutes=tz_offset_minutes)
    today = (datetime.now(UTC) + offset).date()
    start = datetime.combine(today - timedelta(days=6), datetime.min.time()) - offset
    events = db.scalars(
        select(DeliveryEvent)
        .join(Package, DeliveryEvent.package_id == Package.id)
        .join(Route, Package.route_id == Route.id)
        .where(Route.user_id == user.id, DeliveryEvent.timestamp >= start)
    ).all()
    counts: dict[str, Counter] = {}
    for ev in events:
        if not ev.event_type.startswith("status:"):
            continue
        day = (ev.timestamp + offset).date().isoformat()
        counts.setdefault(day, Counter())[ev.event_type.removeprefix("status:")] += 1
    days = [
        WeeklyDay(
            date=(today - timedelta(days=i)).isoformat(),
            delivered=counts.get((today - timedelta(days=i)).isoformat(), Counter())["delivered"],
            failed=counts.get((today - timedelta(days=i)).isoformat(), Counter())["failed_attempt"],
            skipped=counts.get((today - timedelta(days=i)).isoformat(), Counter())["skipped"],
        )
        for i in range(6, -1, -1)
    ]
    delivered = sum(d.delivered for d in days)
    failed = sum(d.failed for d in days)
    skipped = sum(d.skipped for d in days)
    total = delivered + failed + skipped
    return WeeklyOut(
        days=days,
        delivered=delivered,
        failed=failed,
        skipped=skipped,
        success_rate=round(delivered / total, 4) if total else 0.0,
    )

from collections import Counter
from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.db import get_db
from app.models import Route, User
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
    ).all()
    counts = Counter(p.status for r in routes for p in r.packages)
    total = sum(counts.values())
    done = total - counts["pending"]
    active = next((r for r in routes if r.pending_packages), None)
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
        )
        if active
        else None,
    )

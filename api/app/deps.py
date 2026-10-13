import uuid
from datetime import UTC, datetime

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session, selectinload

from app.models import Package, Route, Subscription, User

PLAN_LIMITS = {
    "free": {"max_packages_per_route": 30, "max_import_rows": 30},
    "pro": {"max_packages_per_route": 300, "max_import_rows": 2000},
    "team": {"max_packages_per_route": 300, "max_import_rows": 2000},
}


def get_owned_route(db: Session, route_id: uuid.UUID, user: User) -> Route:
    route = db.scalar(
        select(Route)
        .where(Route.id == route_id)
        .options(selectinload(Route.packages), selectinload(Route.stops))
    )
    if route is None or route.user_id != user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Rota não encontrada")
    return route


def active_subscription(db: Session, user: User) -> Subscription | None:
    sub = db.get(Subscription, user.id)
    if sub is None:
        return None
    expires = sub.expires_at
    if expires is not None and expires.tzinfo is None:
        expires = expires.replace(tzinfo=UTC)
    return sub if expires is None or expires > datetime.now(UTC) else None


def plan_limits(db: Session, user: User) -> tuple[str, dict[str, int]]:
    sub = active_subscription(db, user)
    entitlement = sub.entitlement if sub and sub.entitlement in PLAN_LIMITS else "free"
    return entitlement, PLAN_LIMITS[entitlement]


def ensure_capacity(db: Session, user: User, route: Route, extra: int) -> None:
    _, limits = plan_limits(db, user)
    count = db.scalar(select(func.count()).where(Package.route_id == route.id)) or 0
    if count + extra > limits["max_packages_per_route"]:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            f"Limite do plano: {limits['max_packages_per_route']} pacotes por rota",
        )


def mark_route_changed(route: Route) -> None:
    if route.status in ("validated", "optimized"):
        route.status = "draft"

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.db import get_db
from app.deps import active_subscription, plan_limits
from app.models import User
from app.schemas import SubscriptionOut

router = APIRouter(prefix="/v1/subscription", tags=["subscription"])


@router.get("", response_model=SubscriptionOut)
def get_subscription(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    sub = active_subscription(db, user)
    entitlement, limits = plan_limits(db, user)
    return SubscriptionOut(
        entitlement=entitlement,
        product_id=sub.product_id if sub else None,
        expires_at=sub.expires_at if sub else None,
        source=sub.source if sub else "default",
        limits=limits,
    )

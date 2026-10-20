from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.db import get_db
from app.deps import PLAN_LIMITS, active_subscription, is_pro_email, plan_limits
from app.models import Subscription, User
from app.schemas import PlayPurchaseIn, SubscriptionOut

router = APIRouter(prefix="/v1/subscription", tags=["subscription"])

# Assinaturas configuradas no Play Console -> dias de validade por registro.
# Inclui margem sobre o ciclo: o app reenvia o token a cada abertura,
# renovando a validade enquanto a assinatura seguir ativa na Play.
PLAY_PRODUCTS = {"pro_mensal": 33, "pro_anual": 370}


@router.get("", response_model=SubscriptionOut)
def get_subscription(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if is_pro_email(user):
        return SubscriptionOut(
            entitlement="pro",
            source="owner",
            product_id=None,
            expires_at=None,
            limits=PLAN_LIMITS["pro"],
        )
    sub = active_subscription(db, user)
    entitlement, limits = plan_limits(db, user)
    return SubscriptionOut(
        entitlement=entitlement,
        product_id=sub.product_id if sub else None,
        expires_at=sub.expires_at if sub else None,
        source=sub.source if sub else "default",
        limits=limits,
    )


@router.post("/play", response_model=SubscriptionOut)
def register_play_purchase(
    body: PlayPurchaseIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Registra o purchase token do Google Play e libera o plano Pro.

    O teste grátis de 7 dias é uma oferta da própria Play (com cartão): a
    compra chega aqui já no início do teste e a cobrança ocorre no 8º dia.

    A verificação com a Play Developer API é feita quando a conta de serviço
    estiver configurada; por ora confiamos no token que o próprio Google Play
    Billing já validou no dispositivo.
    """
    days = PLAY_PRODUCTS.get(body.product_id)
    if days is None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Produto desconhecido")
    sub = db.get(Subscription, user.id)
    if sub is None:
        sub = Subscription(user_id=user.id)
    sub.product_id = body.product_id
    sub.entitlement = "pro"
    sub.source = "play"
    sub.expires_at = datetime.now(UTC) + timedelta(days=days)
    db.add(sub)
    db.commit()
    return get_subscription(user, db)

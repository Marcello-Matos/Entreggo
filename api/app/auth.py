import uuid
from functools import lru_cache

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.config import Settings, get_settings
from app.db import get_db
from app.models import User

bearer = HTTPBearer(auto_error=False)


@lru_cache
def _jwks_client(supabase_url: str) -> jwt.PyJWKClient:
    return jwt.PyJWKClient(f"{supabase_url.rstrip('/')}/auth/v1/.well-known/jwks.json")


def decode_token(token: str, settings: Settings) -> dict:
    alg = jwt.get_unverified_header(token).get("alg")
    if alg == "HS256" and settings.supabase_jwt_secret:
        key = settings.supabase_jwt_secret
    elif alg in ("RS256", "ES256") and settings.supabase_url:
        key = _jwks_client(settings.supabase_url).get_signing_key_from_jwt(token).key
    else:
        raise jwt.InvalidTokenError(f"Algoritmo não suportado: {alg}")
    return jwt.decode(token, key, algorithms=[alg], audience=settings.jwt_audience)


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> User:
    if credentials is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Autenticação necessária")
    try:
        claims = decode_token(credentials.credentials, settings)
        user_id = uuid.UUID(claims["sub"])
    except (jwt.PyJWTError, KeyError, ValueError) as exc:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Token inválido") from exc

    user = db.get(User, user_id)
    if user is None:
        user = User(id=user_id, email=claims.get("email"))
        db.add(user)
        db.commit()
    if user.status != "active":
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Conta inativa")
    return user

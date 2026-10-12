import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.config import Settings, get_settings
from app.db import get_db
from app.models import User

bearer = HTTPBearer(auto_error=False)

FIREBASE_JWKS_URL = (
    "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"
)
_jwks_client = jwt.PyJWKClient(FIREBASE_JWKS_URL, cache_keys=True)


def get_signing_key(token: str):
    return _jwks_client.get_signing_key_from_jwt(token).key


def decode_token(token: str, settings: Settings) -> dict:
    """Valida um ID token do Firebase Authentication (RS256, chaves públicas do Google)."""
    project = settings.firebase_project_id
    if not project:
        raise jwt.InvalidTokenError("FIREBASE_PROJECT_ID não configurado")
    claims = jwt.decode(
        token,
        get_signing_key(token),
        algorithms=["RS256"],
        audience=project,
        issuer=f"https://securetoken.google.com/{project}",
        options={"require": ["exp", "iat", "sub"]},
    )
    if not claims["sub"] or len(claims["sub"]) > 128:
        raise jwt.InvalidTokenError("sub inválido")
    return claims


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> User:
    if credentials is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Autenticação necessária")
    try:
        claims = decode_token(credentials.credentials, settings)
    except jwt.PyJWTError as exc:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Token inválido") from exc

    user = db.get(User, claims["sub"])
    if user is None:
        user = User(id=claims["sub"], email=claims.get("email"))
        db.add(user)
        db.commit()
    if user.status != "active":
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Conta inativa")
    return user

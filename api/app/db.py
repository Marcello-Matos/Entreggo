from collections.abc import Iterator

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.config import get_settings


class Base(DeclarativeBase):
    pass


def _database_url() -> str:
    """Aceita a URL como vem dos provedores (Neon/Supabase): remove espaços e
    aspas acidentais e completa o driver psycopg quando ausente."""
    url = get_settings().database_url.strip().strip("\"'")
    if url.startswith("postgresql://"):
        url = f"postgresql+psycopg://{url[len('postgresql://'):]}"
    return url


engine = create_engine(_database_url(), pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, expire_on_commit=False)


def get_db() -> Iterator[Session]:
    with SessionLocal() as session:
        yield session

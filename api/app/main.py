from contextlib import asynccontextmanager

from fastapi import FastAPI
from sqlalchemy import text

from app import models  # noqa: F401  (registra os modelos no metadata)
from app.db import Base, engine
from app.routers import dashboard, import_jobs, packages, routes, subscription, users


@asynccontextmanager
async def lifespan(_: FastAPI):
    # MVP: cria as tabelas na inicialização. Migre para Alembic antes de produção.
    Base.metadata.create_all(engine)
    if engine.dialect.name == "postgresql":
        # Colunas adicionadas depois do primeiro deploy (create_all não altera tabelas)
        with engine.begin() as conn:
            conn.execute(
                text(
                    "ALTER TABLE packages "
                    "ADD COLUMN IF NOT EXISTS vehicle_location VARCHAR(60)"
                )
            )
            conn.execute(
                text(
                    "ALTER TABLE delivery_proofs "
                    "ADD COLUMN IF NOT EXISTS delivery_method VARCHAR(30)"
                )
            )
    yield


app = FastAPI(title="Entreggo API", version="0.1.0", lifespan=lifespan)

for r in (
    routes.router,
    packages.router,
    import_jobs.router,
    subscription.router,
    dashboard.router,
    users.router,
):
    app.include_router(r)


@app.get("/health", tags=["health"])
def health():
    return {"status": "ok"}

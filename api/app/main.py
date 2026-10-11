from contextlib import asynccontextmanager

from fastapi import FastAPI

from app import models  # noqa: F401  (registra os modelos no metadata)
from app.db import Base, engine
from app.routers import import_jobs, packages, routes, subscription


@asynccontextmanager
async def lifespan(_: FastAPI):
    # MVP: cria as tabelas na inicialização. Migre para Alembic antes de produção.
    Base.metadata.create_all(engine)
    yield


app = FastAPI(title="Entreggo API", version="0.1.0", lifespan=lifespan)

for r in (routes.router, packages.router, import_jobs.router, subscription.router):
    app.include_router(r)


@app.get("/health", tags=["health"])
def health():
    return {"status": "ok"}

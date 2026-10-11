# Entreggo — instruções para agentes

Monorepo: `api/` (Python 3.12 + FastAPI) e `app/` (Flutter). Idioma do produto e das mensagens: português (pt-BR).

## API (`api/`)

- Setup: `python3.12 -m venv .venv && .venv/bin/pip install -e ".[dev]"`
- Lint: `.venv/bin/ruff check . && .venv/bin/ruff format --check .`
- Testes: `.venv/bin/pytest -q` (SQLite em memória + geocodificador falso; sem Docker/segredos)
- Rodar: `docker compose up -d db` na raiz, depois `.venv/bin/uvicorn app.main:app --reload`
- Toda rota privada usa `Depends(get_current_user)` e verifica propriedade com `get_owned_route`
  (retorna 404 para recursos de outro usuário).

## App (`app/`)

- `flutter pub get`, `flutter analyze`, `flutter test`, `dart format lib test`
- Configuração via `--dart-define-from-file=env.json` (ver `env.example.json`).
- Dependências: preferir versões publicadas há mais de 7 dias (`supabase_flutter` fixado em 2.18.0).

## Segredos

`SUPABASE_URL`, `SUPABASE_JWT_SECRET`, `GOOGLE_MAPS_API_KEY` (API) e `SUPABASE_PUBLISHABLE_KEY` (app)
nunca vão para o repositório (`.env` e `env.json` estão no `.gitignore`).

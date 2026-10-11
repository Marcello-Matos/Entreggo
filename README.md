# Entreggo — Sua rota. Otimizada.

Aplicativo mobile para entregadores autônomos organizarem pacotes, validarem endereços e
receberem uma sequência sugerida de paradas.

| Pasta    | Conteúdo                                                        |
| -------- | --------------------------------------------------------------- |
| `api/`   | API Python + FastAPI (rotas, pacotes, importação, otimização)   |
| `app/`   | App Flutter (Android + iOS): login, rotas, scanner, otimização  |
| `db/`    | Script de inicialização do PostgreSQL + PostGIS                 |

## Pré-requisitos

- Python 3.11+ (testado com 3.12)
- Flutter stable (testado com 3.47)
- Docker (para o PostgreSQL + PostGIS local)
- Projeto no [Supabase](https://supabase.com) para autenticação

## API

```bash
docker compose up -d db              # PostgreSQL + PostGIS em localhost:5432
cd api
python3.12 -m venv .venv
.venv/bin/pip install -e ".[dev]"
cp .env.example .env                 # preencha SUPABASE_URL / GOOGLE_MAPS_API_KEY
.venv/bin/uvicorn app.main:app --reload
```

Documentação interativa em http://localhost:8000/docs.

- Testes: `.venv/bin/pytest`
- Lint/format: `.venv/bin/ruff check . && .venv/bin/ruff format --check .`

Os testes usam SQLite em memória e um geocodificador falso; não precisam de Docker nem de chaves.

### Endpoints

| Método e rota                        | Uso                                   |
| ------------------------------------ | ------------------------------------- |
| `POST /v1/routes`                    | Criar rota                            |
| `GET /v1/routes`                     | Listar rotas do usuário               |
| `GET /v1/routes/{id}`                | Detalhar rota, pacotes e ordem        |
| `POST /v1/routes/{id}/packages`      | Adicionar pacote manualmente          |
| `POST /v1/routes/{id}/scan`          | Registrar código lido (409 se duplicado) |
| `POST /v1/import-jobs`               | Importar CSV/XLSX (multipart)         |
| `GET /v1/import-jobs/{id}`           | Resultado e erros da importação       |
| `POST /v1/routes/{id}/geocode`       | Validar/geocodificar endereços        |
| `POST /v1/routes/{id}/optimize`      | Calcular sequência sugerida           |
| `PATCH /v1/packages/{id}/status`     | Atualizar status de entrega           |
| `GET /v1/routes/{id}/summary`        | Resumo e métricas                     |
| `GET /v1/subscription`               | Plano e limites efetivos              |

## App

```bash
cd app
cp env.example.json env.json         # preencha as chaves do Supabase
flutter pub get
flutter run --dart-define-from-file=env.json
```

No emulador Android, `10.0.2.2` aponta para o `localhost` da máquina.

- Análise: `flutter analyze`
- Testes: `flutter test`

## Decisões do MVP e próximos passos

- **Autenticação:** Supabase Auth; a API valida o JWT (JWKS ou segredo HS256 legado) e verifica a
  propriedade de cada recurso no servidor.
- **Otimização:** OR-Tools com matriz de distância em linha reta (haversine), rota aberta a partir
  do ponto inicial. Próximo passo: trocar por matriz de tempo/distância do fornecedor de mapas.
- **Geocodificação:** Google Geocoding API (opcional; sem chave o endpoint retorna 503).
- **Banco:** tabelas criadas no startup (`create_all`). Migrar para Alembic antes de produção.
- **Limites de plano:** definidos no servidor (`app/deps.py`); assinaturas via RevenueCat ainda
  não integradas.
- Pendentes: ponto inicial pelo GPS, mapa, correção manual de endereço, modo offline,
  importação pelo app, webhooks do RevenueCat, política de retenção de arquivos.

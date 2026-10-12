# Entreggo — Sua rota. Otimizada.

Aplicativo mobile para entregadores autônomos: escaneie os pacotes (código de barras,
foto da etiqueta ou planilha/PDF), o app valida os endereços, monta a rota otimizada a
partir do seu GPS e guia as entregas pelo Google Maps ou Waze, parada a parada.

| Pasta    | Conteúdo                                                                 |
| -------- | ------------------------------------------------------------------------ |
| `api/`   | API Python + FastAPI (rotas, pacotes, importação, geocodificação, otimização) |
| `app/`   | App Flutter (Android + iOS): login, scanner, OCR de etiqueta, modo entrega |
| `db/`    | Script de inicialização do PostgreSQL + PostGIS (opcional)               |

## Pré-requisitos

- Python 3.11+ (testado com 3.12)
- Flutter stable
- PostgreSQL 16 (local ou hospedado; PostGIS opcional por enquanto)
- Projeto no [Firebase](https://console.firebase.google.com) com Authentication
  (E-mail/senha e Google) ativados

## API

```bash
cd api
python3.12 -m venv .venv
.venv/bin/pip install -e ".[dev]"
cp .env.example .env                 # preencha DATABASE_URL e FIREBASE_PROJECT_ID
.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8001
```

`--host 0.0.0.0` permite que o iPhone na mesma rede Wi-Fi acesse a API pelo
endereço `http://<nome-do-mac>.local:8001`.

Documentação interativa em http://localhost:8001/docs.

- Testes: `.venv/bin/pytest`
- Lint/format: `.venv/bin/ruff check . && .venv/bin/ruff format --check .`

Os testes usam SQLite em memória e um geocodificador falso; não precisam de banco
nem de chaves externas.

### Variáveis de ambiente (`api/.env`)

| Variável               | Uso                                                            |
| ---------------------- | -------------------------------------------------------------- |
| `DATABASE_URL`         | `postgresql+psycopg://user:senha@host:5432/entreggo`             |
| `FIREBASE_PROJECT_ID`  | ID do projeto Firebase (valida os tokens de login)             |
| `GOOGLE_MAPS_API_KEY`  | Opcional. Com chave, geocodifica pelo Google; sem, usa OpenStreetMap |
| `NOMINATIM_URL`        | URL do serviço Nominatim (geocodificador gratuito padrão)      |
| `NOMINATIM_CONTACT`    | E-mail de contato exigido pela política de uso do Nominatim    |

### Endpoints

| Método e rota                        | Uso                                        |
| ------------------------------------ | ------------------------------------------ |
| `POST /v1/routes`                    | Criar rota                                 |
| `GET /v1/routes`                     | Listar rotas do usuário                    |
| `GET /v1/routes/{id}`                | Detalhar rota, pacotes e ordem             |
| `PATCH /v1/routes/{id}`              | Renomear rota                              |
| `DELETE /v1/routes/{id}`             | Excluir rota e todo o conteúdo             |
| `POST /v1/routes/{id}/packages`      | Adicionar pacote manualmente               |
| `POST /v1/routes/{id}/scan`          | Registrar código lido (409 se duplicado)   |
| `POST /v1/import-jobs`               | Importar CSV/XLSX/PDF (multipart)          |
| `GET /v1/import-jobs/{id}`           | Resultado e erros da importação            |
| `POST /v1/routes/{id}/geocode`       | Validar/geocodificar endereços             |
| `POST /v1/routes/{id}/optimize`      | Calcular sequência (partida: GPS ou endereço) |
| `PATCH /v1/packages/{id}`            | Corrigir endereço do pacote                |
| `PATCH /v1/packages/{id}/status`     | Atualizar status de entrega                |
| `DELETE /v1/packages/{id}`           | Remover pacote da rota                     |
| `GET /v1/routes/{id}/summary`        | Resumo e métricas                          |
| `GET /v1/subscription`               | Plano e limites efetivos                   |

## App

```bash
cd app
cp env.example.json env.json         # preencha API_BASE_URL
flutter pub get
flutter run --dart-define-from-file=env.json
```

`env.json` (não vai para o git):

```json
{
  "API_BASE_URL": "http://localhost:8001"
}
```

Para testar num iPhone na mesma rede, crie `env.iphone.json` com
`"API_BASE_URL": "http://<nome-do-mac>.local:8001"`.

A configuração do Firebase é gerada pelo FlutterFire (`firebase_options.dart`,
`GoogleService-Info.plist`, `google-services.json`) — são chaves públicas de
cliente, já commitadas.

- Análise: `flutter analyze`
- Testes: `flutter test`

## Fluxo de uso

1. **Iniciar entregas de hoje** — cria a rota e abre o scanner.
2. **Scanner** — código de barras/QR contínuo; se o código não trouxer endereço,
   fotografe a etiqueta (OCR nativo do iOS lê o endereço impresso) ou digite.
   Etiquetas sem código legível entram direto pela foto.
3. **Importar** — planilha CSV/XLSX ou romaneio PDF (menu da rota). Pacotes da
   planilha casam com o código escaneado depois.
4. **Montar rota** — geocodifica tudo (com variações de consulta), usa o GPS
   como partida e otimiza a ordem. Endereços não encontrados entram na revisão.
5. **Modo entrega** — uma parada por vez: Google Maps ou Waze, depois marque
   Entregue / Não entregue / Pular.

## Decisões do MVP e próximos passos

- **Autenticação:** Firebase Auth (e-mail/senha e Google); a API valida o token
  com as chaves públicas do Google e verifica a propriedade de cada recurso.
- **Geocodificação:** OpenStreetMap/Nominatim por padrão (gratuito, ~1 req/s);
  com `GOOGLE_MAPS_API_KEY` usa o Google. Consultas com variações (rua+cidade,
  rua+CEP) quando o endereço completo falha.
- **OCR de etiqueta:** framework Vision do iOS via canal nativo; parser de
  endereço brasileiro em `app/lib/scanning/label_parser.dart`.
- **Otimização:** OR-Tools com distância em linha reta (haversine), rota aberta
  a partir do GPS ou de um endereço de partida. Próximo passo: matriz de tempo
  real de trânsito.
- **Banco:** tabelas criadas no startup (`create_all`). Migrar para Alembic
  antes de produção.
- **Limites de plano:** no servidor (`app/deps.py`); assinaturas via RevenueCat
  ainda não integradas.
- Pendentes: deploy da API + Postgres na nuvem, mapa no app, modo offline,
  política de retenção de arquivos, TestFlight/Play Store.

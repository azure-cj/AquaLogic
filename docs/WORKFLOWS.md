# AquaLogic Development Workflows

Status: Current local workflow
Last reviewed: 2026-07-27

## First-time setup

### Backend

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\activate
pip install -r requirements-dev.txt
copy .env.example .env
alembic upgrade head
python -m seed.seed_data
```

### Web

```powershell
cd web
npm install
```

### Mobile

```powershell
cd mobile_app
flutter pub get
```

## Daily local run

From the repository root:

```powershell
.\start-dev.bat
```

This starts the API at `http://127.0.0.1:8000` and the Vite web app at
`http://localhost:5173`, with the local-only demo sensor generator enabled.
It keeps the seeded fleet fresh with representative normal, warning, critical,
and offline states. API documentation is available at `http://127.0.0.1:8000/docs`.

For manual control, run the backend and web commands in separate terminals:

```powershell
cd backend
\.venv\Scripts\activate
python -m uvicorn app.main:app --reload
```

```powershell
cd web
npm run dev
```

## Validation workflow

Run the smallest check that proves the change, then the complete checks for the
affected application.

```powershell
cd backend
pytest -q
alembic upgrade head
pip-audit
```

```powershell
cd web
npm run typecheck
npm test
npm run build
npm audit --omit=dev
```

```powershell
cd mobile_app
flutter analyze
flutter test
```

For changes that affect public/admin behavior, also run the browser smoke or
visual regression workflow and preserve only intentional evidence under
`docs/browser-artifacts/`.

## Database changes

1. Update the SQLAlchemy model and corresponding schema/service behavior.
2. Create a new Alembic revision from `backend/`.
3. Run `alembic upgrade head` against a fresh temporary database.
4. Add or update API tests for the behavior.
5. Do not edit or commit local `*.db` files as a substitute for a migration.

## API change workflow

1. Update backend schema/model/route behavior.
2. Update affected backend tests.
3. Update the web API models/client and UI consumers.
4. Check mobile impact even though the current mobile prototype is not yet
   connected.
5. Update `docs/API_CONTRACT.md` and `docs/DEVELOPMENT_STATUS.md` if the public
   behavior or status changed.

## Documentation workflow

At the end of a meaningful task:

- Update the relevant area guide if structure or commands changed.
- Update architecture/domain/API docs if behavior or boundaries changed.
- Add a decision entry for cross-cutting choices.
- Update the status checkpoint only when implementation status changed.
- Keep task-specific notes in the task response or issue, not in permanent docs.

## Deployment preparation

Deployment configuration is present in `render.yaml` and `web/vercel.json`, but
deployment is not complete. Before a production release, configure a real
PostgreSQL database, a unique 32-byte JWT secret, explicit CORS origins and
trusted hosts, a public base URL, controlled image hosts, and disabled
debug/demo flags. Verify login, refresh rotation, public QR privacy, migration,
headers, CORS, RBAC, and sensor-ingestion smoke tests before release.

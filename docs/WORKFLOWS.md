# AquaLogic Development Workflows

Status: Current local workflow
Last reviewed: 2026-08-21

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

For a temporary classroom demo from another laptop, double-click
`start-classroom-demo.bat`. It starts the local API and web app, waits for the
Vite server, checks that `ngrok` is installed, and exposes port `5173` through
an HTTPS ngrok URL. Keep all opened terminal windows running and prevent the
host computer from sleeping while presenting. This is a temporary tunnel, not
a production deployment.

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

When staff setup or password-reset links are generated, the backend uses
`PUBLIC_BASE_URL` as the browser URL. Keep the local default
`http://localhost:5173` when the recipient is using the same computer; for a
temporary classroom demo, set it to the active HTTPS web/tunnel URL before
creating the account link. Setup links are single-use and expire after 30
minutes, so generate a fresh link if an older one was opened or reset.

For the temporary ESP32 sensor/actuator bridge, follow
[`ESP32_BRIDGE_HARDWARE_TEST_RUNBOOK.md`](ESP32_BRIDGE_HARDWARE_TEST_RUNBOOK.md).
Use the nested repository's owner/tester launcher files or run:

```powershell
python bridge\esp32_bridge.py --config bridge\bridge-config.json --once
python bridge\esp32_bridge.py --config bridge\bridge-config.json
```

The bridge configuration is local and untracked. The ESP32 URL must remain a
private local `/data` address; a temporary tunnel may carry only dashboard/API
traffic. The browser and backend never call the ESP32 directly.

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

## Local backup and isolated restore

Local recovery is supported for file-backed SQLite only. From `backend/`, create
a paired database/media bundle outside the repository or under the ignored
`backend/backups/` directory:

```powershell
cd backend
python -m scripts.backup_local `
  --output-dir .\backups `
  [--database-url sqlite:///C:/path/to/aqualogic.db] `
  [--media-root C:\path\to\media]
```

The bundle contains `aqualogic.db`, `media/`, and a checksummed `manifest.json`.
It never packages environment files, JWT secrets, credentials, device keys, or
bridge configuration.

Restore only into a new, isolated directory:

```powershell
cd backend
python -m scripts.restore_local `
  --bundle .\backups\aqualogic-backup-<UTC timestamp>.tar.gz `
  --target-dir ..\restore\aqualogic-<UTC timestamp>
```

The restore command rejects an existing target, validates archive paths and
checksums, applies Alembic migrations, runs SQLite integrity checks, and
revokes every restored session while incrementing every restored user's token
version. There is no live-restore flag or HTTP restore endpoint. Start a
separate validation process with the restored database and media paths only
after the command completes.

Validate an isolated restore with `/health`, administrator login, staff read
access, administrator-only access, public tank privacy, restored media URLs,
and restored device/actuator mappings. Production recovery must not run demo
seeding or demo sensor generation.

Production PostgreSQL backups and point-in-time recovery remain the deployment
or database-provider responsibility. Production media storage must have a
compatible retention and recovery plan; the application does not duplicate
provider-native PostgreSQL backup automation.

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

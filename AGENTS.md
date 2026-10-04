# AquaLogic Agent Instructions

This file is the operating guide for Codex and other coding agents working in
this repository. It is intentionally concise; durable project knowledge lives
in `docs/`.

## Start-of-task reading order

1. Read this file and `docs/INDEX.md`.
2. Read `docs/DEVELOPMENT_STATUS.md` and the relevant area document under
   `docs/areas/`.
3. Inspect the current source code and tests before proposing changes.
4. Check `git status --short` and preserve unrelated user changes.

If documentation conflicts with source code or tests, source code and tests are
authoritative. Update the affected documentation after confirming the current
behavior.

## Product and repository

AquaLogic is a local-first aquarium monitoring and operations system for JRed
Aquatics. The repository contains:

- `backend/`: FastAPI API, SQLAlchemy models, Alembic migrations, seed data,
  decision engine, demo sensor service, and pytest tests.
- `web/`: React + TypeScript + Vite public tank experience and staff/admin
  dashboard.
- `mobile_app/`: Flutter Android-first staff app connected to the deployed
  backend for auth, Home, Tanks, Alerts, Monitoring, Species, read-only
  Equipment, and Firebase push; mock repositories remain for tests and
  features without an API.
- `bridge/`: temporary laptop bridge that forwards ESP32 sensor readings to the
  backend and runs allowlisted admin actuator commands against the local ESP32.
  Tests: `python -m pytest bridge/tests -q` from the repository root.
- `Aqualogic.ino` and the library folders: ESP32 firmware and sensor/display
  dependencies. Hardware integration is a later phase.
- `docs/`: canonical project context, architecture, contracts, workflows, and
  historical plans.

## Engineering rules

- Keep the local-first direction unless the task explicitly changes it.
- Treat the backend API and database model as shared contracts for future web,
  mobile, and hardware clients.
- Any schema change requires an Alembic migration under
  `backend/alembic/versions/`.
- Do not add hardware dependencies to software-only features.
- Do not commit secrets, `.env` files, local databases, dependency folders, or
  build output.
- Preserve existing user changes and do not reset or overwrite unrelated work.
- Prefer small, focused changes with tests close to the changed behavior.
- Use the existing project conventions before introducing a new dependency or
  architectural pattern.

## Validation commands

From the repository root:

```powershell
.\start-dev.bat
```

Backend:

```powershell
cd backend
pytest -q
alembic upgrade head
python -m seed.seed_data
python -m uvicorn app.main:app --reload
```

Web:

```powershell
cd web
npm install
npm run typecheck
npm test
npm run build
```

Mobile:

```powershell
cd mobile_app
flutter pub get
flutter analyze
flutter test
```

Run the smallest relevant checks while iterating, then run the complete checks
for the affected application before handoff.

## Documentation maintenance

Update documentation when a change affects behavior, architecture, API shape,
scope, setup, deployment, or a known limitation. Add a dated entry to
`docs/DECISIONS.md` for an important choice. Update
`docs/DEVELOPMENT_STATUS.md` when work moves between planned, active, and
completed.

Do not treat old planning documents as current implementation instructions.
Their status and role are recorded in `docs/INDEX.md`.

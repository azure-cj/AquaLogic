# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

AquaLogic is a local-first aquarium monitoring and operations system for JRed Aquatics. The git repo root is this `AquaLogic/` directory (the parent folder is only a workspace container). Windows/PowerShell is the primary dev environment.

`AGENTS.md` and `docs/INDEX.md` are the other entry points. Source code and tests are authoritative over docs; `docs/history/` and `docs/deep-spec/` are planning/spec material, not current implementation instructions. Read `docs/DEVELOPMENT_STATUS.md` and the relevant `docs/areas/*.md` guide before non-trivial work.

## Components

- `backend/` — FastAPI + SQLAlchemy + Alembic (SQLite locally, PostgreSQL in production).
- `web/` — React 18 + TypeScript + Vite: public `/tank/:publicId` pages and the `/admin/*` staff dashboard.
- `mobile_app/` — Flutter, Android-first staff app.
- `bridge/esp32_bridge.py` — temporary laptop bridge between the ESP32 on a private LAN and the backend.
- `Aqualogic.ino` + `DallasTemperature/`, `OneWire/`, `LiquidCrystal_I2C/`, `DIYables_LCD_I2C/` — ESP32 firmware and vendored Arduino libs. No build tooling in the repo (Arduino IDE only); don't edit the vendored libs.

## Commands

Backend (from `backend/`, venv at `backend/.venv`):

```powershell
.\.venv\Scripts\Activate.ps1
pytest -q                                   # full suite
pytest -q tests/test_actuators.py           # one file
pytest -q tests/test_actuators.py::test_name  # one test
alembic upgrade head
python -m seed.seed_data                    # local demo data only (14 days of readings, varied fleet states)
python -m uvicorn app.main:app --reload     # API on :8000, docs at /docs
```

Web (from `web/`; use `npm ci` for installs):

```powershell
npm run dev                                 # :5173, staff app at /admin
npm run typecheck
npm test                                    # vitest run
npm test -- --run src/features/tanks/ActuatorControlPanel.test.tsx
npm test -- --run -t "test name"
npm run build                               # tsc -b && vite build
```

Mobile (from `mobile_app/`):

```powershell
flutter pub get
flutter analyze
flutter test
flutter test test/splash_screen_test.dart   # one file; add --plain-name "..." for one test
```

Bridge (from repo root): `python -m pytest bridge/tests -q`.

Docs link check: `python scripts/check_markdown_links.py`.

Whole local stack: `.\start-dev.bat` (opens API + web terminals with the demo sensor enabled via `DEMO_SENSOR_ENABLED` and `DEMO_SENSOR_INSTANCE`). Backend config lives in `backend/.env` (copy from `.env.example`; never commit it). Keep runtime packages in `requirements.txt`, test/audit tooling in `requirements-dev.txt`.

Git: short-lived branches from `main` with conventional-prefix commits (`feat:`, `fix:`, `docs:` …) and PRs into `main`; stage specific files rather than `git add .` (`docs/GIT_WORKFLOW.md`).

## Architecture

**Data flow.** A reading arrives either manually from staff or from a registered device via the bridge using a per-device key. The device key resolves to exactly one server-side tank; bridge requests can never choose a tank. `services/decision_engine.py` evaluates the reading against the tank's effective thresholds (a complete per-tank override, else the global default — `services/thresholds.py`) and creates, escalates, downgrades or auto-resolves `Alert` rows. A separate lifespan-owned loop (`services/monitoring_incidents.py`) detects reporting outages and records `MonitoringIncident` rows. These are distinct concepts: water-quality alerts vs. monitoring outages, and neither is the same as species-care suitability (`services/species_suitability.py`, a derived, staff-only read path that shares only the 90-second freshness helper).

**Backend app startup** (`backend/app/main.py`): the lifespan starts the demo sensor generator, the periodic maintenance loop (outage detection + actuator-command reconciliation) and, if enabled, the push dispatcher. Non-production startup also runs `create_all` and seeds default thresholds; production schema is owned only by Alembic and startup rejects unsafe config (non-PostgreSQL URL, missing secrets). Security headers, request-size limits and CORS/trusted hosts are applied in `main.py` middleware.

**Time semantics matter.** Freshness, reporting health, uptime and monitoring use server `received_at`. Water-quality analytics trends use observation time. Alert events use alert creation time. Don't swap them.

**Actuator control (physical safety boundary).** Admin-only. The backend queues server-generated, expiring commands bound to a device's fixed tank. The bridge claims one with the device key, makes one allowlisted local call to the ESP32, and reports `executing`/`succeeded`/`failed`/`outcome_unknown`. Hardware calls are never auto-retried after an ambiguous response; claimed commands that pass the confirmation window become terminal `outcome_unknown` via shared idempotent reconciliation; same-device/same-pump dispense is serialized (row lock on PostgreSQL, `BEGIN IMMEDIATE` on SQLite). The browser and backend never talk to the ESP32 directly, and the web client never sees device keys or ESP32 URLs. Staff get 403 on actuator routes. Pump schedules and auto-dosing are intentionally outside the command allowlist.

**Tank lifecycle.** Active-tank writes go through `services/tank_lifecycle.py` guards. Retirement is a one-way, admin-only transition that locks the tank, forces it private, deactivates devices and resolves open incidents. Deletion is database-first, then best-effort media cleanup confined to `media_root`. Moving hardware = deactivate old device + provision a new one; a device's tank mapping is never edited.

**Push notifications.** Alert creation, monitoring-incident open and reporting-recovery enqueue an idempotent outbox event (unique `event_key`, one delivery per event/device) inside the source transaction; a separate dispatcher leases deliveries and sends via Firebase Admin outside it. Firebase is transport only, never a source of identity/authorization. Disabled by default (`PUSH_NOTIFICATIONS_ENABLED`); credentials exist only as a deployment secret.

**Auth.** Argon2id passwords, a 15-minute HS256 access JWT held in memory only (web and mobile), a rotating opaque refresh token (HttpOnly Strict cookie on web, Android secure storage on mobile), per-request checks of token version and active `AuthSession`, DB-backed throttling and an append-only audit log. Roles are `admin` and `staff` (mobile shows them as Owner/Staff). Authorization is enforced on the backend; hiding UI is never the boundary. Don't add browser storage for auth state.

**Web structure.** `src/app/` (providers, router, lazy `route-loaders.ts` — keep route code lazy), `src/features/<feature>/` (feature-first pages), `src/shared/` (API client, models, components), `src/layouts/admin/`. Use the `@/` import alias. Keep new surfaces on semantic theme tokens and update `dark-theme.css` for any hardcoded light colors.

**Mobile structure.** `lib/app/*_scope.dart` are inherited-widget scopes that inject repositories; each feature under `lib/features/` has a mock repository and an `Api*Repository` (DTO mapping from snake_case/numeric IDs) behind the same seam. Tests inject the mocks; production composition uses the API repositories via the shared authenticated `ApiClient` (`lib/shared/network/`). The server's status and freshness are authoritative — the client must not compute its own offline thresholds or turn network failures into tank outages. No background polling; refresh is pull-to-refresh and on resume.

## Conventions and gotchas

- **Migrations:** any schema change needs an Alembic migration in `backend/alembic/versions/` (numbered `00NN_*`, currently head `0019`). Never edit an already-deployed migration. Keep them SQLite- and PostgreSQL-compatible (SQLite batch ops locally, native ops on PG); revision IDs over 32 chars rely on the `alembic_version` widening in `0012`.
- **Backend tests don't use Alembic.** `tests/conftest.py` builds an in-memory SQLite schema with `create_all` and drives the app through a sync `httpx.ASGITransport` wrapper (`client` fixture; `auth_headers` logs in as an admin). A model change that is missing its migration will still pass pytest — verify with a clean `alembic upgrade head` against a throwaway SQLite DB.
- Use dependency-injected DB sessions, Pydantic schemas at API boundaries, and add regression tests for auth, visibility, threshold, alert and data-integrity behavior.
- Dissolved oxygen and ammonia are deferred: nullable in the API/DB, skipped by threshold evaluation, hidden in UI. The four installed sensors are temperature, pH, turbidity and TDS; Species Care suitability checks only temperature, pH and TDS.
- Public endpoints expose a reduced projection (no tank codes, feeding schedules, or numeric thresholds; rounded readings).
- Mobile and bridge are consumers of the backend contract: the legacy `GET /alerts` response shape (no `page` params) is still used by mobile, so keep it backward-compatible (`docs/API_CONTRACT.md`).
- The bridge's pump manual-test mode is default-off and must be used with water or empty syringes only.
- Don't commit `.env`, local DBs (`aqualogic.db`), `media/`, build output, or bridge-local outbox files. `.operator-review/` is untracked local material.
- After behavior, API, architecture or scope changes, update the relevant `docs/` file; add a dated entry to `docs/DECISIONS.md` for important decisions and update `docs/DEVELOPMENT_STATUS.md` when work changes state.

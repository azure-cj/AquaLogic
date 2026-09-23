# Backend Area Guide

Status: Current
Last reviewed: 2026-09-23

## Read first

- [`../ARCHITECTURE.md`](../ARCHITECTURE.md)
- [`../DOMAIN_MODEL.md`](../DOMAIN_MODEL.md)
- [`../API_CONTRACT.md`](../API_CONTRACT.md)
- [`../WORKFLOWS.md`](../WORKFLOWS.md)

## Important locations

- `backend/app/main.py`: application creation, startup, middleware, routers.
- `backend/app/config.py`: environment-driven settings, production validation,
  and normalized database URL handling.
- `backend/app/models/`: SQLAlchemy entities.
- `backend/app/schemas/`: API request/response validation.
- `backend/app/routes/`: HTTP route modules.
- `backend/app/services/decision_engine.py`: sensor status and alert rules.
  Threshold comparisons are strict at configured boundaries; active alerts can
  escalate, downgrade, and resolve automatically on the next fresh normal
  value for the same parameter. It uses the tank's complete override when
  present and otherwise the global default.
- `backend/app/services/thresholds.py`: shared effective-threshold resolution
  and analytics history that falls back to the global timeline after resets.
- `backend/app/services/species_suitability.py`: derived species preference
  checks; keep this policy separate from threshold and alert behavior.
- `backend/app/routes/tanks.py`: tank detail, active/retired/all directory
  filters, one-way retirement, configuration, assignments, the compact
  `/operations` snapshot contract, hero-image upload/replacement, and
  database-first permanent deletion cleanup for owned local tank media.
- `backend/app/services/tank_lifecycle.py`: centralized active-tank guards,
  retirement actuator checks, and SQLite/PostgreSQL mutation-lock ordering;
  this service also maintains the explicit monitoring-expectation boundary.
- `backend/app/routes/devices.py`: one-time admin provisioning, sanitized
  administrator device lifecycle management, device-key bridge ingestion, with
  server-side tank mapping, actuator command claiming, final reporting, and
  actuator-state reporting.
- `backend/app/routes/management.py` and `backend/app/routes/security.py`:
  administrator account lifecycle summaries, sanitized session management,
  and filtered security audit access.
- `backend/app/routes/fish.py`: fish species directory and admin-only species
  photo upload storage under the configured media root.
- `backend/app/models/device.py`: registered devices, actuator command ledger,
  current actuator state, and append-only actuator state history.
- `backend/app/schemas/device.py`: strict UV, normal LED, feeder, and guarded
  Pump A/B command/state contracts, including timer, schedule, firmware
  configuration bounds, configured-volume dispense monitoring, and pump expiry
  limits.
- `backend/alembic/versions/0008_actuator_controls.py`: actuator command/state
  schema migration.
- `backend/alembic/versions/0009_domain_foundation.py`: sensor reading source
  device and server receipt timestamp migration with SQLite-safe backfill.
- `backend/alembic/versions/0010_alert_resolution_source.py`: additive alert
  operator/system resolution metadata migration.
- `backend/alembic/versions/0011_actuator_uncertain_outcomes.py`: actuator
  confirmation deadlines, persistent unknown outcomes, and verification audit
  metadata migration.
- `backend/alembic/versions/0012_retired_tank_lifecycle.py`: additive tank
  retirement metadata, monitoring expectation, indexes, and active-row
  backfill.
- `backend/alembic/versions/0014_tank_threshold_overrides.py`: optional
  complete tank overrides and append-only override/reset history.
- `backend/app/services/demo_sensor.py`: opt-in local sensor generator.
- `backend/app/services/auth_security.py`: refresh rotation, login throttling,
  setup links, and security audit recording.
- `backend/alembic/versions/`: schema migrations.
- `backend/scripts/backup_local.py`: standard-library-only paired SQLite/media
  backup bundle creation.
- `backend/scripts/restore_local.py`: checksum-validated, isolated-only restore
  with migration, integrity checks, and restored-session invalidation.
- `backend/tests/`: endpoint and behavior coverage.

## Conventions

- Use dependency-injected database sessions.
- Keep authorization checks on the backend even when the web UI hides actions.
- Use Pydantic schemas at API boundaries.
- Use migrations for schema changes.
- Route tank-owned writes through the centralized active-tank guard. Retirement
  is administrator-only, one-way, idempotent, and must lock the tank before
  deactivating its devices; retired history remains readable without reopening
  operational writes.
- Keep actuator routes admin-only for browser users. Device-key routes must
  resolve the device's fixed tank and must not accept a client-selected tank.
- Treat queued command expiry and `queued -> executing` claiming as part of the
  physical safety boundary. Do not add an automatic hardware retry after a
  command may have executed.
- Add regression tests for auth, visibility, threshold, alert, and data-integrity
  behavior.
- Alert freshness is based on server `received_at` with a 90-second window.
  Missing values are unavailable; a fresh reading uses the worst present,
  enabled severity and becomes offline when no usable value exists. External
  notification delivery is deferred; in-app alerts are the current surface.
- Runtime packages belong in `requirements.txt`; pytest, HTTP clients, and
  audit tooling belong in `requirements-dev.txt`.

## Database configuration

Development and tests may use SQLite; when `DATABASE_URL` is absent, the
backend defaults to `sqlite:///./aqualogic.db`. With
`ENVIRONMENT=production`, `DATABASE_URL` is required and must point to
PostgreSQL. Production rejects missing, malformed, and SQLite URLs instead of
falling back. `postgres://` is normalized to `postgresql://`; the synchronous
SQLAlchemy backend uses `psycopg2-binary`. Alembic escapes percent signs while
passing the URL through ConfigParser so percent-encoded credentials survive.

The migration chain keeps SQLite batch alterations for local development and
uses native PostgreSQL column/constraint alterations for referenced tables in
revisions `0009` and `0012`. `0010` uses a Boolean `IS TRUE` predicate in both
database dialects. SQLite-only connection arguments, foreign-key pragmas, and
`BEGIN IMMEDIATE` writer locks remain guarded by the SQLite dialect.

## Common checks

```powershell
cd backend
pytest -q
alembic upgrade head
pip-audit
```

Local recovery checks use the operator scripts documented in
[`../WORKFLOWS.md`](../WORKFLOWS.md). They accept file-backed SQLite only;
production PostgreSQL backups remain provider-managed.

Actuator-specific backend checks include:

```powershell
cd backend
pytest -q tests/test_actuators.py tests/test_device_ingestion.py
alembic upgrade head
```

The actuator API stores validated payloads and results as JSON, never device
keys or Wi-Fi credentials. The existing generic actuator tables also store the
manual-test pump lifecycle; no extra migration is needed for this JSON-backed
extension. UV, LED, and feeder schedules are validated configuration commands
forwarded once to the ESP32, which owns local execution; AquaLogic does not run
a command scheduler or create one command per autonomous event. Its existing
periodic maintenance loop also reconciles overdue actuator commands without a
browser request. Command history is paginated with a bounded
`page_size` and optional actuator/status filters so the admin audit view cannot
grow into an unbounded response. Each history response also includes lifecycle
counts for the fixed device/tank, independent of the active row filters, so the
dashboard can distinguish the current filtered view from overall command
activity. A stale/offline bridge exposes last-known state and does not claim
that the physical actuator is off. Pump commands are rejected rather than
queued while the fixed bridge is offline, and backend authorization remains
admin-only. Normal commands default to 120-second expiry with a 300-second
maximum; pump commands default to 20 seconds with a 30-second maximum. Hardware
requests are never automatically retried after an ambiguous result; confirmed
pre-dispatch failures remain `failed`, while post-dispatch ambiguity becomes
`outcome_unknown`. A claimed
command that passes the 180-second post-claim confirmation window becomes
terminal `outcome_unknown`; reconciliation is shared and idempotent across
create, read, pending, claim, and report entry points. Same-device/same-pump
dispense is interlocked while executing or uncleared unknown, with PostgreSQL
row serialization and SQLite `BEGIN IMMEDIATE`; administrator verification
records actor/time/note and clears only the software lock. Late bridge reports
return `409` and do not rewrite the terminal unknown record.

The current database defaults to `backend/aqualogic.db` when the backend is run
from its directory. It is local state, not a source artifact.

Tank retirement/deletion captures the current lifecycle and hardware boundary.
Retirement forces private visibility, deactivates registered devices in the
same transaction, and retains history; it does not erase firmware schedules or
physical state. Tank deletion captures the current `/api/media/tanks/` hero path, commits the
relational delete and audit event first, then best-effort removes only a file
contained by `settings.media_root`. External URLs, missing files, and paths
outside the media root are ignored; post-commit unlink failures are logged and
do not make the committed deletion appear to have failed. It does not clear
device-resident schedules or physical equipment. Follow the decommissioning and
move/reprovisioning procedures in
[`../WORKFLOWS.md#moving-equipment-to-another-tank`](../WORKFLOWS.md#moving-equipment-to-another-tank).

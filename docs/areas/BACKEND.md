# Backend Area Guide

Status: Current
Last reviewed: 2026-08-17

## Read first

- [`../ARCHITECTURE.md`](../ARCHITECTURE.md)
- [`../DOMAIN_MODEL.md`](../DOMAIN_MODEL.md)
- [`../API_CONTRACT.md`](../API_CONTRACT.md)
- [`../WORKFLOWS.md`](../WORKFLOWS.md)

## Important locations

- `backend/app/main.py`: application creation, startup, middleware, routers.
- `backend/app/config.py`: environment-driven settings and production CORS
  validation.
- `backend/app/models/`: SQLAlchemy entities.
- `backend/app/schemas/`: API request/response validation.
- `backend/app/routes/`: HTTP route modules.
- `backend/app/services/decision_engine.py`: sensor status and alert rules.
- `backend/app/services/species_suitability.py`: derived species preference
  checks; keep this policy separate from threshold and alert behavior.
- `backend/app/routes/tanks.py`: tank detail, configuration, assignments, and
  the compact `/operations` snapshot contract.
- `backend/app/routes/devices.py`: one-time admin provisioning and device-key
  bridge ingestion, with server-side tank mapping, actuator command claiming,
  final reporting, and actuator-state reporting.
- `backend/app/models/device.py`: registered devices, actuator command ledger,
  current actuator state, and append-only actuator state history.
- `backend/app/schemas/device.py`: strict UV, normal LED, feeder, and guarded
  Pump A/B command/state contracts, including timer, schedule, firmware
  configuration bounds, configured-volume dispense monitoring, and pump expiry
  limits.
- `backend/alembic/versions/0008_actuator_controls.py`: actuator command/state
  schema migration.
- `backend/app/services/demo_sensor.py`: opt-in local sensor generator.
- `backend/app/services/auth_security.py`: refresh rotation, login throttling,
  setup links, and security audit recording.
- `backend/alembic/versions/`: schema migrations.
- `backend/tests/`: endpoint and behavior coverage.

## Conventions

- Use dependency-injected database sessions.
- Keep authorization checks on the backend even when the web UI hides actions.
- Use Pydantic schemas at API boundaries.
- Use migrations for schema changes.
- Keep actuator routes admin-only for browser users. Device-key routes must
  resolve the device's fixed tank and must not accept a client-selected tank.
- Treat queued command expiry and `queued -> executing` claiming as part of the
  physical safety boundary. Do not add an automatic hardware retry after a
  command may have executed.
- Add regression tests for auth, visibility, threshold, alert, and data-integrity
  behavior.
- Runtime packages belong in `requirements.txt`; pytest, HTTP clients, and
  audit tooling belong in `requirements-dev.txt`.

## Common checks

```powershell
cd backend
pytest -q
alembic upgrade head
pip-audit
```

Actuator-specific backend checks include:

```powershell
cd backend
pytest -q tests/test_actuators.py tests/test_device_ingestion.py
alembic upgrade head
```

The actuator API stores validated payloads and results as JSON, never device
keys or Wi-Fi credentials. The existing generic actuator tables also store the
manual-test pump lifecycle; no extra migration is needed for this JSON-backed
extension. Command history is paginated with a bounded
`page_size` and optional actuator/status filters so the admin audit view cannot
grow into an unbounded response. Each history response also includes lifecycle
counts for the fixed device/tank, independent of the active row filters, so the
dashboard can distinguish the current filtered view from overall command
activity. A stale/offline bridge exposes last-known state and does not claim
that the physical actuator is off. Pump commands are rejected rather than
queued while the fixed bridge is offline, and backend authorization remains
admin-only.

The current database defaults to `backend/aqualogic.db` when the backend is run
from its directory. It is local state, not a source artifact.

# Backend Area Guide

Status: Current
Last reviewed: 2026-07-28

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
- `backend/app/services/demo_sensor.py`: opt-in local sensor generator.
- `backend/alembic/versions/`: schema migrations.
- `backend/tests/`: endpoint and behavior coverage.

## Conventions

- Use dependency-injected database sessions.
- Keep authorization checks on the backend even when the web UI hides actions.
- Use Pydantic schemas at API boundaries.
- Use migrations for schema changes.
- Add regression tests for auth, visibility, threshold, alert, and data-integrity
  behavior.

## Common checks

```powershell
cd backend
pytest -q
alembic upgrade head
```

The current database defaults to `backend/aqualogic.db` when the backend is run
from its directory. It is local state, not a source artifact.

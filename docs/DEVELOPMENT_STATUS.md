# AquaLogic Development Status

Status: Current checkpoint
Last reviewed: 2026-07-27

## Completed and working locally

### Backend

- FastAPI application with SQLAlchemy models and Alembic migrations.
- JWT authentication, active-user checks, roles, and forced password changes.
- Tank, fish species, tank-fish assignment, customer, and staff management.
- Sensor reading persistence and threshold-backed status evaluation.
- Warning/critical alert creation, listing, filtering, and resolution.
- Public tank API using UUID-style public IDs.
- Fleet overview, threshold administration, and fleet analytics endpoints.
- Optional demo sensor generation behind two explicit flags.
- Backend behavior covered by pytest tests.

### Web

- Public mobile-first `/tank/:publicId` experience.
- Staff/admin routes for fleet, alerts, tanks, fish, customers, analytics, staff,
  and thresholds.
- Lazy route loading, feature-first structure, shared API client, responsive
  layouts, and accessible loading/dialog patterns.
- Local typecheck, tests, and production build have been recorded as passing in
  `docs/WEB_DASHBOARD_IMPLEMENTATION_REPORT.md`.

### Mobile

- Flutter Android-first dashboard prototype with home, tanks, sensor cards,
  alerts, fish library, controls, and navigation shell.
- Local mock readings and demo control interactions.

## Active follow-up work

- Run a complete browser regression pass after the latest web refactor.
- Add CI for backend tests, migrations, web typecheck/tests/build, and browser
  smoke coverage.
- Reconcile the Flutter app with the backend API contract before implementing
  authentication or live data.
- Finalize deployment environment variables and production smoke tests.

## Planned

- Backend client integration for the Flutter app.
- ESP32 sensor ingestion and actuator control.
- Raspberry Pi deployment and hardware safety controls.
- Schedules for feeding, lighting, filtration, dosing, and water replacement.
- Pagination and database-level analytics for larger datasets.
- Stronger JWT revocation/rotation procedures.

## Known limitations

- Cloud resources are configured in files but have not been provisioned or
  validated end to end.
- SQLite is the normal local database; PostgreSQL production behavior remains
  to be exercised.
- Dashboard list endpoints do not yet paginate.
- Fleet analytics aggregates selected periods in application memory.
- The current public API exposes the latest configured sensor values; this needs
  a final privacy and threat review before production.
- Staff management does not yet prevent removing the final active administrator.
- The mobile application is not a backend-connected client.
- WebSocket streaming is not implemented.

## Validation checkpoint — 2026-07-27

- Backend: `pytest -q` passed with 16 tests and one third-party deprecation
  warning.
- Web: `npm run typecheck` passed.
- Web: `npm test` passed with 29 tests across 7 test files.
- Mobile: validation is pending a Flutter/Dart SDK compatible with the
  `mobile_app/pubspec.yaml` requirement (`^3.12.1`); the available Dart SDK is
  3.12.0.

## Status update convention

When work changes status, update this file with a short dated note and link to
the implementation report, decision, issue, or relevant source files. Do not
use this document as a detailed task log.

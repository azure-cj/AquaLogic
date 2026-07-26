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
- Fleet analytics provide complete bucket timelines, three-tank overlays,
  historical threshold segments, exact alert events, previous-period
  comparisons, reporting-gap diagnostics, and classified uptime.
- Optional demo sensor generation behind two explicit flags.
- The local seed workflow creates seven days of deterministic demo sensor
  history, representative normal/warning/critical/offline fleet states, alert
  history, and populated public-tank details.
- Backend behavior covered by pytest tests.
- Fish species expose care groups, categorical diets, and tank usage counts;
  assigned species are protected from deletion.

### Web

- Public mobile-first `/tank/:publicId` experience.
- Staff/admin routes for fleet, alerts, tanks, fish, customers, analytics, staff,
  and thresholds.
- Lazy route loading, feature-first structure, shared API client, responsive
  layouts, and accessible loading/dialog patterns.
- Floating-island navigation uses one grouped configuration and adapts from
  flat links to clustered menus as the viewport or navigation count requires.
- Local typecheck, tests, and production build have been recorded as passing in
  `docs/WEB_DASHBOARD_IMPLEMENTATION_REPORT.md`.
- Fish species use a grouped directory by default with a remembered compact-list
  alternative, diet badges, thumbnails, filters, and assignment-aware actions.
- Analytics support URL-persisted range/resolution/tank/metric controls,
  threshold and alert overlays, synchronized parameter previews, aligned
  comparison charts, operational insights, deep links, and filtered CSV export.

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
- Fleet analytics stream required reading columns and aggregate them in the
  application; custom windows are therefore capped at 30 days and 1,000
  buckets.
- The current public API exposes the latest configured sensor values; this needs
  a final privacy and threat review before production.
- Staff management does not yet prevent removing the final active administrator.
- The mobile application is not a backend-connected client.
- WebSocket streaming is not implemented.

## Validation checkpoint — 2026-07-27

- Backend: `pytest -q` passed with 18 tests and one third-party deprecation
  warning.
- Database: `alembic upgrade head` reached
  `0005_analytics_threshold_history`.
- Web: `npm run typecheck` and `npm run build` passed.
- Web: `npm test` passed with 38 tests across 9 test files.
- Browser: authenticated analytics regression passed at desktop, tablet, and
  mobile widths with no console errors or document-level horizontal overflow.
- Mobile: validation is pending a Flutter/Dart SDK compatible with the
  `mobile_app/pubspec.yaml` requirement (`^3.12.1`); the available Dart SDK is
  3.12.0.

## Status update convention

When work changes status, update this file with a short dated note and link to
the implementation report, decision, issue, or relevant source files. Do not
use this document as a detailed task log.

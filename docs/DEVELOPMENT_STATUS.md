# AquaLogic Development Status

Status: Current checkpoint
Last reviewed: 2026-08-15

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
- Staff tank drawers show dynamic species-care suitability against the latest
  fresh reading. Results are not persisted alerts, and preferred range changes
  and assignment changes take effect immediately.
- Authentication now uses Argon2id passwords, a claim-complete 15-minute JWT,
  revocable rotating refresh sessions, one-time setup links, database-backed
  login throttling, audit events, strict production configuration, and
  role-enforced write permissions.
- The public tank contract now exposes a privacy-safe display location only,
  omits tank codes and feeding schedules, and rounds public readings.
- Temporary ESP32 bridge testing is implemented: registered device keys map to
  fixed tanks, ingest only four supported `/data` measurements, audit requests,
  and represent dissolved oxygen/ammonia as unavailable. See
  `ESP32_BRIDGE_HARDWARE_TEST_RUNBOOK.md`.
- v1 admin-only actuator bridge controls are implemented for UV, normal LED, and
  fish feeder, plus a guarded Pump A/B manual-test phase. Pump commands use
  expiring server records, fixed device/tank mapping, strict dispense cutoffs,
  idempotent claim/report transitions, validated local state, and the existing
  append-only command/state audit trail. The bridge preserves sensor polling,
  uses only the registered device key, keeps pump testing default-off, and never
  retries a potentially executed hardware call.

### Web

- Public mobile-first `/tank/:publicId` experience.
- Staff/admin routes for fleet, alerts, tanks, fish, customers, analytics, staff,
  and thresholds.
- Tank workspaces keep a compact actuator snapshot while administrators can open
  the focused `/admin/tanks/:tankId/actuators` control center for full timers,
  schedules, guarded pump tests, and paginated command history.
- The Configure navigation group now exposes an administrator-only Actuators
  chooser beside Thresholds; it lists tanks and links into their scoped control
  workspaces without exposing device credentials or ESP32 endpoints.
- The web shell now supports persistent System, Light, and Dark themes through
  one accessible appearance control shared by the admin, authentication, and
  public tank surfaces; dark-mode tokens cover panels, controls, overlays,
  actuator history, and analytics/public status surfaces. Deliberate changes
  use a short origin-aware teal ink-bloom transition with a reduced-motion
  fallback.
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

- Staff tank workspace is implemented locally: `/admin/tanks/:tankId` adds
  live operations, dynamic Species Care, assignment management, and a shared
  configuration drawer; browser regression remains to be completed.

- Run a complete browser regression pass after the latest web refactor.
- Perform the one-device/one-tank UV/LED/feeder and controlled Pump A/B hardware
  test using the temporary dashboard/API tunnel and confirm local-only ESP32
  access. Pump testing must use empty syringes or water only.
- Add CI for backend tests, migrations, web typecheck/tests/build, and browser
  smoke coverage.
- Reconcile the Flutter app with the backend API contract before implementing
  authentication or live data.
- Finalize deployment environment variables and production smoke tests.

## Planned

- Backend client integration for the Flutter app.
- Additional sensor hardware and production-grade actuator safety controls;
  pump schedules and pH auto-dose remain deferred.
- Raspberry Pi deployment and hardware safety controls.
- Schedules for feeding, lighting, filtration, dosing, and water replacement.
- Pagination and database-level analytics for larger datasets.

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
- The mobile application is not a backend-connected client.
- Actuator state is last-known state from the bridge; a stale/offline bridge does
  not imply the physical actuator is off.
- Tunnel infrastructure is temporary test infrastructure only. The ESP32 must
  remain on the tester's private Wi-Fi and is never publicly exposed.
- WebSocket streaming is not implemented.
- `npm audit --omit=dev` reports GHSA-qwww-vcr4-c8h2 for the mandated
  `react-router-dom@7.18.1`. AquaLogic is a Vite SPA and does not enable the
  advisory's React Server Components mode, but the package has no patched 7.x
  release; keep this deployment exception under review until upstream ships a
  compatible fix.

## Validation checkpoint — 2026-08-15

- Backend: `pytest -q` passed with 49 tests, including fixed device/tank
  mapping, admin/staff authorization, pump offline rejection and payload
  bounds, expiry, atomic claim and idempotent reporting, state history, and
  preserved sensor ingestion.
- Bridge: `pytest -q ..\bridge\tests` passed with 43 tests covering every
  allowlisted UV, LED, feeder, and Pump A/B translation, pump safety cutoffs,
  invalid firmware responses, unreachable endpoints, safe one-shot command
  behavior, default-off pump configuration, and private-URL validation.
- Database: `DATABASE_URL=sqlite:///./.actuator-validation.db alembic upgrade
  head` reached `0008_actuator_controls`; the temporary validation database was
  removed afterward.
- Web: `npm run typecheck`, `npm test` (70 tests across 16 files), and
  `npm run build` passed.

## Validation checkpoint — 2026-07-29

- Backend: `pytest -q` passed with 33 tests; `alembic current` is
  `0006_auth_security_hardening (head)` and `pip-audit -r requirements.txt`
  found no known vulnerabilities.
- Web: `npm run typecheck`, `npm test` (46 tests), and `npm run build` passed.
- Runtime dependency audit: the React Router advisory above is the only
  reported runtime finding; no compatible remediation exists for the requested
  `react-router-dom@7.18.1` version.

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

# AquaLogic Development Status

Status: Current checkpoint
Last reviewed: 2026-08-21

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
- Fish species expose care groups, categorical diets, supported preferred water
  ranges, assigned-tank summaries, tank usage counts, explicit directory
  filters, and a readable details drawer; assigned species are protected from
  deletion.
- Staff tank drawers show dynamic species-care suitability against the latest
  fresh reading. Results are not persisted alerts, and preferred range changes
  and assignment changes take effect immediately.
- Tank create/edit now uses a focused public-profile form with URL or validated
  admin hero-image upload support; customer assignment remains an internal
  relationship while its demo workflow is being redesigned.
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
  expiring server records, fixed device/tank mapping, firmware-configured mL
  doses, bounded completion monitoring, idempotent claim/report transitions,
  validated local state, and the existing append-only command/state audit trail.
  The bridge preserves sensor polling, uses only the registered device key,
  keeps pump testing default-off, and never retries a potentially executed
  hardware call.
- Phase 06 access hardening is implemented: staff/admin/public/device permission
  boundaries, authentication lifecycle revocation, setup-link replay/expiry,
  last-administrator protection, security headers, cookie flags, throttling, and
  administrator-only security audit access are regression-tested.
- SQLite foreign-key enforcement is enabled for application and test engines;
  cascade, nullable-reference, uniqueness, assignment-protection, and rollback
  behavior are covered by integrity tests.
- Local recovery tooling is implemented under `backend/scripts/`: paired
  SQLite-plus-media bundles include versioned manifests and checksums, while
  restores are isolated-only, migration-aware, integrity-checked, and revoke
  restored sessions. Production PostgreSQL backup ownership remains with the
  deployment/database provider.
- Account lifecycle hardening is implemented: administrator user summaries
  derive account status, password state, active session counts, and latest
  activity; administrator-only user detail/session/revoke endpoints expose no
  raw secrets; and the audit feed supports account, event, outcome, and time
  filters.
- Phase 02 monitoring-engine hardening is implemented: strict threshold ordering
  and boundary semantics, prospective threshold revisions, receipt-time
  freshness, worst-available tank status derivation, automatic alert
  escalation/downgrade/resolution, operator/system resolution metadata, and
  audited threshold-disable resolution. External notification delivery remains
  deferred.

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
  alternative, diet badges, hosted or uploaded JPG/PNG/WebP thumbnails,
  care-group/diet/usage filters, readable details, preferred-range editing,
  assigned-tank links, and assignment-aware actions.
- Analytics support URL-persisted range/resolution/tank/metric controls,
  threshold and alert overlays, synchronized parameter previews, aligned
  comparison charts, operational insights, deep links, and filtered CSV export.
- Account Center now explains personal identity, password state, role access,
  and administrator team metrics. Its role-capability explanation is kept in an
  accessible header popover. Staff & roles is an administrator-only lifecycle
  workspace with searchable/filterable status, activity and session metadata,
  confirmation-gated actions, and a detail drawer for access, sessions, and
  per-user audit activity. The drawer groups routine refreshes and progressively
  reveals bounded history with load-more/show-fewer controls.
- Phase 01 domain foundation hardening is implemented: administrator device
  lifecycle management, sanitized device inventory, one-time key rotation,
  reading source-device and server receipt provenance, shared manual/device
  bounds validation, receipt-time freshness, and the administrator Devices
  workspace. Multiple active devices per tank remain supported; stable sample
  IDs and dissolved-oxygen/ammonia hardware integration remain deferred.
- Phase 02 web hardening is implemented: threshold forms provide strict-order
  feedback, deferred parameters remain hidden, and alert history identifies
  automatic versus operator resolution while retaining the in-app-only
  notification surface.
- Phase 03 species-care contract hardening is implemented: suitability evaluates
  only temperature, pH, and TDS using receipt-time freshness, the public tank
  response uses a reduced species and sensor projection, and legacy dissolved
  oxygen/ammonia fields remain database-only compatibility data for these
  workflows. Species assignment remains staff/admin-accessible, audit logged,
  and compatibility notes remain informational with pairwise compatibility
  deferred.

### Documentation

- Phase 04 operations hardening is implemented: fleet analytics uses server
  `received_at` for operational bucketing, uptime, and reporting gaps while
  preserving observation timestamps for history; the public tank page labels
  its observation time as “Observed”. Fleet, tank, alert, analytics, and public
  contracts remain backward-compatible.
- Phase 05 equipment-control documentation is reconciled with the current
  actuator routes, bridge translator, web controls, and focused regression
  tests. The docs now distinguish device-resident UV/LED/feeder schedules from
  backend scheduling, record exact command expiry and no-blind-retry behavior,
  and keep Pump A/B maintenance separate from automatic chemical dosing.

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
  access. Verify the configured firmware-reported mL dose completes before the
  bridge timeout. Pump testing must use empty syringes or water only.
- Add CI for backend tests, migrations, web typecheck/tests/build, and browser
  smoke coverage.
- Reconcile the Flutter app with the backend API contract before implementing
  authentication or live data.
- Finalize deployment environment variables and production smoke tests.

## Planned

- Backend client integration for the Flutter app.
- Additional sensor hardware and production-grade actuator safety controls;
  pump schedules, pH auto-dose, and backend scheduler workers remain deferred.
- Raspberry Pi deployment and hardware safety controls.
- Timezone-aware schedule management, device-clock synchronization, and
  schedule-event history for device-resident feeding and lighting schedules.
- Schedules for filtration, dosing, and water replacement.
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

## Validation checkpoint — 2026-08-21

- Backend Phase 01, Phase 02, Phase 04, and Phase 06 regression suite: `.venv\Scripts\python.exe -m
  pytest -q tests/test_permissions.py tests/test_data_integrity.py
  tests/test_backup_recovery.py tests/test_security_hardening.py
  tests/test_account_lifecycle.py tests/test_device_ingestion.py
  tests/test_monitoring_engine.py tests/test_dashboard_management.py` passed
  alongside the complete backend suite
  (95 tests).
- Validation includes staff/admin/public/device authorization boundaries,
  authentication revocation, SQLite foreign-key behavior, paired backup
  manifest checksums, isolated restore, migration, media preservation, and
  restored-session invalidation, receipt-time monitoring, threshold boundary
  behavior, alert lifecycle transitions, receipt-time analytics, and public
  timestamp wording.
- Backend complete suite: `pytest -q` passed with 95 tests; the existing
  database and a fresh temporary database reached `0010_alert_resolution_source`;
  `pip-audit -r requirements.txt`
  reported no known vulnerabilities.
- Web: `npm run typecheck`, `npm test` (88 tests across 21 files), and
  `npm run build` passed. The latest UI polish covered the account capability
  popover, drawer history limits, lifecycle wording, session expiry context,
  bridge telemetry grouping, Account Center spacing, threshold validation
  feedback, and alert resolution-source labels. The browser smoke reached the
  login surface and confirmed unauthenticated session bootstrap is rejected;
  authenticated browser flows remain covered by the backend regression suite.

## Validation checkpoint — 2026-08-17

- Backend: `pytest -q` passed with 49 tests, including fixed device/tank
  mapping, admin/staff authorization, pump offline rejection and empty
  configured-volume payload validation, expiry, atomic claim and idempotent
  reporting, state history, and preserved sensor ingestion.
- Bridge: `pytest -q ..\bridge\tests` passed with 44 tests covering every
  allowlisted UV, LED, feeder, and Pump A/B translation, configured-volume
  completion monitoring, one-shot safety-stop behavior, invalid firmware
  responses, unreachable endpoints, default-off pump configuration, bounded
  completion timeout configuration, and private-URL validation.
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

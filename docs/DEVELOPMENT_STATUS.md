# AquaLogic Development Status

Status: Current checkpoint
Last reviewed: 2026-09-15

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
  `operations/hardware/ESP32_BRIDGE_HARDWARE_TEST_RUNBOOK.md`.
- v1 admin-only actuator bridge controls are implemented for UV, normal LED, and
  fish feeder, plus a guarded Pump A/B manual-test phase. Pump commands use
  expiring server records, fixed device/tank mapping, firmware-configured mL
  doses, bounded completion monitoring, idempotent claim/report transitions,
  validated local state, and the existing append-only command/state audit trail.
  The bridge preserves sensor polling, uses only the registered device key,
  keeps pump testing default-off, and never retries a potentially executed
  hardware call.
- Goal 1 actuator uncertainty hardening is implemented: claimed commands have a
  persisted 180-second post-claim confirmation deadline, idempotent
  `executing -> outcome_unknown` reconciliation, deterministic late-report
  rejection, same-device/same-pump dispense interlocks, and administrator-only
  physical-verification clearance with actor/time/note metadata. Stop remains
  available during the pump lock; post-dispatch bridge failures are now
  reported as `outcome_unknown` rather than generic `failed`, and the existing
  periodic maintenance loop reconciles overdue commands without a browser
  request. No bridge retry or replay path was added.
- Goal 2 tank deletion cleanup is implemented: permanent deletion captures the
  current tank hero URL, commits the relational cascade first, and then
  best-effort removes only contained AquaLogic-owned local media. Missing,
  external, and out-of-root paths are safe no-ops; post-commit filesystem
  failures are logged without reversing the committed delete. Permanent
  deletion now takes the same SQLite/PostgreSQL lifecycle lock as retirement.
  Both web deletion
  dialogs enumerate the major relational, media, and public-page consequences
  without claiming that device-resident schedules or physical state are cleared.
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
- Local typecheck, tests, and production build are recorded in the dated
  validation checkpoints below; the older
  `docs/history/reports/WEB_DASHBOARD_IMPLEMENTATION_REPORT.md` is retained as historical
  context only.
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
  feedback and strict/open boundary guidance, deferred parameters remain
  hidden, and alert history distinguishes automatic recovery from the
  operator-facing Mark handled action while retaining the in-app-only
  notification surface.
- Phase 03 species-care contract hardening is implemented: suitability evaluates
  only temperature, pH, and TDS using receipt-time freshness, the public tank
  response uses a reduced species and sensor projection, and legacy dissolved
  oxygen/ammonia fields remain database-only compatibility data for these
  workflows. Species assignment remains staff/admin-accessible, audit logged,
  and compatibility notes remain informational with pairwise compatibility
  deferred.
- Goal 3 monitoring and Species Care UI clarity is implemented: stale/offline
  values are labeled as last-known context using server receipt age, tank
  operations explain operational status separately from Species Care, manual
  alert handling is presented as Mark handled without changing the backend
  lifecycle, Species Care is explicitly water-only, and strict/open threshold
  boundaries are explained without algorithm changes.
- Final terminology polish is implemented: public pages describe recorded
  water-quality attention without claiming notification or human response,
  private publication is separate from Offline monitoring, monitoring incidents
  use an explicit outage label, and Fleet desktop visibly marks stale readings
  as last known.
- Goal 4 retired-tank lifecycle is implemented: administrators can perform the
  idempotent one-way `active -> retired` transition with bounded note and audit
  metadata; retirement forces private visibility, clears the explicit
  monitoring expectation, deactivates registered devices transactionally, and
  preserves readings, alerts, assignments, configuration, media, and actuator
  history. Active/retired/all tank filters, live fleet exclusion, historical
  analytics opt-in, centralized active-write guards, retired read-only detail,
  and retirement-before-delete are covered by backend and web tests. Goal 5
  persistent monitoring incidents are now implemented separately: eligible
  active tanks receive one idempotently detected outage row after the
  configurable grace period, accepted readings recover it, and device
  disablement or retirement resolves it with explicit reasons.

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
  and keep Pump A/B maintenance separate from automatic chemical dosing. The
  current lifecycle also records claimed-but-unconfirmed outcomes as
  `outcome_unknown` rather than expired or failed, and documents the
  same-device/same-pump physical-verification lock. Bridge uncertainty reports,
  autonomous reconciliation, and permanent-delete concurrency are now included
  in the current implementation record.
- Tank decommissioning and device movement documentation is reconciled with the
  fixed server-side device/tank mapping: operators deactivate the old identity,
  physically move and verify equipment, provision a new destination identity,
  and recreate only intended device-resident schedules. Permanent deletion
  remains a separate destructive operation and does not imply hardware cleanup.
- Goal 5 persistent unattended monitoring incidents are documented across the
  API, architecture, domain, workflow, Phase 02/04 guidance, and packet 09.
  The in-app history is distinct from water-quality alerts and analytics gap
  reconstruction; external notification delivery remains deferred.

### Mobile

- Flutter Android-first dashboard prototype with home, tanks, sensor cards,
  alerts, fish library, equipment status, and navigation shell.
- Local mock readings and demo equipment interactions.
- Flutter mock sign-in interface with clearly isolated local development
  accounts for the Owner/admin and Staff roles.
- Role-aware authenticated mobile shell that maps backend-compatible `admin` to
  the mobile `Owner` experience and `staff` to the mobile `Staff` experience.
- Local sign-out from More/Account; shared dashboard features remain on local
  demo data.
- Role-aware Home V1 with distinct Owner and Staff information hierarchies while
  sharing the same AquaLogic design system, tank rows, attention cards,
  monitoring summary, and recent activity components.
- Backend-compatible Home presentation for `normal`, `warning`, `critical`, and
  `offline` operational tank states; offline monitoring remains separate from
  water-quality alerts.
- Local `HomeDashboardData` and `MockHomeRepository` boundary for future API
  replacement without rebuilding Home widgets. The fabricated health
  percentage is no longer the primary Home summary.

### Mobile UI/UX refinement — 2026-09-15

- Reworked the authenticated shell to four destinations: Home, Tanks, Alerts,
  and More. Equipment is contextual to an Owner's tank and is not a top-level
  navigation destination; Staff receive a read-only equipment view.
- Added a polished Tanks directory/detail flow with needs-attention and offline
  filters, freshness labels, normal/warning/critical/offline semantics,
  temperature/pH/turbidity/TDS readings, split water-quality and monitoring
  issues, species snapshots, a dedicated retired lifecycle label, and recent
  activity. Retired tanks are not collapsed into Offline or alert severity.
- Added separate Water quality and Monitoring alert streams with Active and
  History views. Water alerts use warning/critical severity, monitoring outages
  stay operational and neutral, and local Mark handled acknowledgement does
  not claim recovery.
- Added Fish species directory/detail views with search, water-type filters,
  preferred ranges, care notes, assigned-species context, and distinct
  suitable/attention/unavailable suitability states.
- Added contextual Owner Equipment for UV, LED, automatic feeder, Pump A, and
  Pump B with separate device connectivity, safe confirmations, and a local
  queued/executing/succeeded/failed/expired/outcome-unknown command lifecycle.
- Reworked More/Account, Sync/local data, About, identity, role, and sign-out
  surfaces and removed fabricated notification, haptic, and critical-only
  preference controls.
- Added shared semantic status/freshness/empty-state components and mock
  repository seams for tanks, alerts, fish, and equipment. Added widget and
  repository tests for role visibility, stream separation, offline semantics,
  suitability states, command safety, and responsive screen content.

Mobile authentication, Home data, and this UI/UX refinement are intentionally
frontend-only. FastAPI/HTTP integration, JWT access tokens, refresh sessions,
secure credential storage, backend `/auth/*` integration, persistent login,
live sensor sync, persisted alerts and monitoring incidents, sensor history,
backend species and assignment APIs, real actuator commands/device
connectivity, command reconciliation, push notifications, and production
equipment safety controls are not yet implemented in the Flutter client.

## Active follow-up work

- Staff tank workspace is implemented locally: `/admin/tanks/:tankId` adds
  live operations, dynamic Species Care, assignment management, and a shared
  configuration drawer. Automated web regression is recorded below; an
  interactive browser smoke and responsive/accessibility review remains a
  manual follow-up.
- Perform the one-device/one-tank UV/LED/feeder and controlled Pump A/B hardware
  test using the temporary dashboard/API tunnel and confirm local-only ESP32
  access. Verify the configured firmware-reported mL dose completes before the
  bridge timeout. Pump testing must use empty syringes or water only.
- Validate Goal 1 timing and safety on hardware: allow a normal command to
  complete within the bridge's permitted timing without becoming unknown,
  exercise a deliberately interrupted/ambiguous report path, confirm the dashboard shows
  the pump lock and keeps Stop available, record physical verification, and
  confirm no duplicate dispense occurs. Use empty syringes or water only.
- Validate Goal 5 in a bounded deployment scenario: apply migration `0013`,
  start one detector worker, confirm an eligible outage persists once, restart
  the worker without duplicating the incident, submit an accepted reading, and
  confirm the incident resolves while any water-quality alert from that same
  reading remains independent. PostgreSQL locking behavior remains a target
  deployment validation item.
- Complete the physical tank-decommissioning checklist before any permanent
  deletion involving registered equipment: disable schedules, stop and verify
  equipment locally, deactivate the old device, confirm no further readings or
  commands arrive, and provision a new identity if hardware is reused.
- Add CI for backend tests, migrations, web typecheck/tests/build, and browser
  smoke coverage.
- Reconcile the Flutter app with the backend API contract before implementing
  authentication or live data.
- Finalize deployment environment variables and production smoke tests.

## Planned

- External monitoring notifications, delivery workers, and escalation remain
  deferred.
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
- `outcome_unknown` is intentionally conservative: it records that a claimed
  command may have executed, not that it definitely did or did not. Production
  hardware timing and emergency-stop behavior remain pending validation.
- Tunnel infrastructure is temporary test infrastructure only. The ESP32 must
  remain on the tester's private Wi-Fi and is never publicly exposed.
- WebSocket streaming is not implemented.
- `npm audit --omit=dev` reports GHSA-qwww-vcr4-c8h2 for the mandated
  `react-router-dom@7.18.1`. AquaLogic is a Vite SPA and does not enable the
  advisory's React Server Components mode, but the package has no patched 7.x
  release; keep this deployment exception under review until upstream ships a
  compatible fix.

## Validation checkpoint — 2026-08-22

- Goal 1 focused backend tests: `pytest -q tests/test_actuators.py` passed with
  19 tests, including file-backed SQLite concurrent reconciliation; the final
  complete backend suite passed with 124 tests.
- Goal 4 lifecycle coverage passed in the final backend suite, including
  retirement blocking for executing/uncleared actuator work, idempotent
  retirement, active/retired/all filtering, historical analytics opt-in,
  retired read-only behavior, device deactivation, permanent-delete gating,
  audit metadata, and media-preserving history.
- Goal 5 focused monitoring tests: `pytest -q tests/test_monitoring_incidents.py`
  passed with 11 tests, covering controllable grace-period boundaries,
  detector re-entry/restart idempotence, first-device and reactivation grace,
  accepted-reading recovery without water-alert suppression, invalid/heartbeat
  non-recovery, multi-device eligibility, retirement/deletion lifecycle,
  authenticated pagination/filtering, and concurrent file-backed SQLite
  detector cycles.
- Alembic validation: an isolated SQLite upgrade reached the current head,
  including `0011_actuator_uncertain_outcomes`, `0012_retired_tank_lifecycle`,
  and `0013_persistent_monitoring_incidents`; the migrations preserve existing
  command rows and backfill confirmation deadlines only for rows already in
  `executing`. Existing active-device tanks receive a fresh monitoring
  expectation at `0012`; `0013` adds the incident table and unresolved-row
  uniqueness index without inventing historical outage rows.
- Bridge suite: `pytest -q` in `bridge` passed with 45 tests; the existing
  one-shot hardware-call and no-blind-retry behavior remains covered.
- Web validation: `npm run typecheck`, `npm test` (98 tests across 24 files),
  and `npm run build` all passed.
- Repository validation: `git diff --check` passed, and the local Markdown-link
  audit resolved every current documentation target.
- Goal 2 focused backend media/integrity/permission/tank tests passed with 22
  tests; affected web tank deletion tests passed with 6 tests. Database-first
  commit failure, missing/external/out-of-root media, post-commit unlink
  failure, owned-file cleanup, cascade behavior, and staff denial are covered.
- Goal 3 focused web tests passed with 15 tests across formatting, fleet,
  alerts, tank workspace, and thresholds. No backend contract or migration
  change was required because authenticated tank operations already expose
  reading `received_at` and fleet already exposes `reporting_age_seconds`.
- Physical hardware validation remains pending. The safe one-device/one-tank
  UV/LED/feeder, water-only or empty-syringe Pump A/B, actuator-uncertainty,
  and tank-decommissioning checklist is recorded in
  `operations/hardware/ESP32_BRIDGE_HARDWARE_TEST_RUNBOOK.md`.

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

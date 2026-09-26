# AquaLogic Development Status

Status: Current checkpoint
Last reviewed: 2026-09-26

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
- A one-off `python -m app.cli.create_admin` command bootstraps only the first
  administrator from required `ADMIN_BOOTSTRAP_EMAIL`,
  `ADMIN_BOOTSTRAP_PASSWORD`, and `ADMIN_BOOTSTRAP_NAME` values. It uses the
  standard Argon2id hash, is safe to rerun, and does not create demo data.
- The public tank contract now exposes a privacy-safe display location only,
  omits tank codes and feeding schedules, and rounds public readings.
- Temporary ESP32 bridge testing is implemented: registered device keys map to
  fixed tanks, ingest only four supported `/data` measurements, audit requests,
  and represent dissolved oxygen/ammonia as unavailable. See
  `operations/hardware/ESP32_BRIDGE_HARDWARE_TEST_RUNBOOK.md`.
- The bridge drains the ESP32 offline backlog after successful live polls
  (batched, acked only after backend confirmation, capped per cycle) and
  backfills estimated `observed_at` timestamps spread evenly over the outage
  interval, since the ESP32 has no real-time clock. Estimates are flagged
  `time_estimated=true` in logs/docs only; persisting the flag is a backend
  follow-up (see `DECISIONS.md`).
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
- PostgreSQL readiness code is in place: production requires a PostgreSQL
  `DATABASE_URL`, the synchronous driver is declared, percent-encoded Alembic
  URLs are supported, and migrations `0009`, `0010`, and `0012` use
  SQLite/PostgreSQL-compatible operations. A live PostgreSQL migration check is
  still pending.
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
  audited threshold-disable resolution. Global defaults now support optional
  complete per-tank overrides with audited reset-to-global history and shared
  effective-threshold evaluation. M6.5 enqueues one transactional push event
  for each new Alert, MonitoringIncident opening, and successful reporting
  recovery. Repeated Alert updates and administrative or water-quality
  resolution do not create push events; Firebase delivery remains secondary to
  source operational persistence.

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
  notification surface. Global thresholds are labeled as defaults; the tank
  workspace shows inherited/overridden effective thresholds with admin edit and
  reset actions, and analytics suppresses shared bands when selected tanks
  differ.
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
  reconstruction. M6.5 connects these source transitions to the transactional
  push outbox.

### Mobile

- Flutter Android-first dashboard prototype with home, tanks, sensor cards,
  alerts, fish library, equipment status, and navigation shell.
- M1 mobile authentication is connected directly to the Railway FastAPI auth
  routes through a shared `ApiClient` and `ApiAuthService`. Release defaults to
  the Railway root URL; debug defaults to the Android emulator host alias with
  a compile-time URL override for local/physical-device development.
- Access JWTs remain in memory. The opaque refresh-cookie value is held by
  Android secure storage, restored through `/auth/refresh` plus `/auth/me`,
  rotated when returned, and cleared on invalid session or local logout.
- Protected requests refresh once on expiry/401 with shared in-flight refresh;
  Login handles safe validation/throttle/network messages, and forced password
  change gates the authenticated shell.
- `MockAuthService` and feature mocks remain injectable for tests. M3 Tanks,
  M4 Alerts/Monitoring, and M5 Species/read-only Equipment now use Railway API
  repositories. The More/Account card displays `/auth/me` identity and active
  status; profile editing and account-organization data have no current API.
- Local mock readings and demo equipment interactions.
- Flutter sign-in screen with isolated mock-only development accounts for the
  Owner/admin and Staff roles.
- Role-aware authenticated mobile shell that maps backend-compatible `admin` to
  the mobile `Owner` experience and `staff` to the mobile `Staff` experience.
- More/Account logout revokes the server session when reachable and always
  clears local auth state; mock repositories remain available for tests and
  screens not yet connected to the API.
- Role-aware Home V1 with distinct Owner and Staff information hierarchies while
  sharing the same AquaLogic design system, tank rows, attention cards,
  monitoring summary, and recent activity components.
- Backend-compatible Home presentation for `normal`, `warning`, `critical`, and
  `offline` operational tank states; offline monitoring remains separate from
  water-quality alerts.
- `HomeRepository` has mock and API implementations. `ApiHomeRepository`
  shares the authenticated client and loads fleet status, unresolved alerts,
  and the current active-monitoring incident page. Fleet status/freshness stay
  server-authoritative; the Home omits unavailable activity instead of showing
  demo actions. The fabricated health percentage is not the primary summary.
- Home exposes loading, full error/retry, partial secondary-source failure,
  and stale-on-refresh states. It refreshes on pull and on resume when the last
  successful load is at least one minute old; it does not poll in the
  background. Live Home links do not open mock detail screens with API IDs.
- M2 Home, M3 Tanks, M4 Alerts/Monitoring, and M5 Species/Equipment are
  read-only apart from the existing safe Mark handled alert action. Account
  editing, activity, and historical sensor charts remain unsupported.

#### M3 — Read-only Tanks directory and detail — 2026-09-25

- `ApiTankRepository` reads the active directory from `/fleet` without per-tank
  list calls. Detail combines tank metadata, operations/current readings,
  active monitoring incidents, and assigned-species suitability through the
  existing authenticated `ApiClient`.
- Existing `TankInfo`, directory/detail screens, repository seam, mock data,
  Home routes, search, and status filters are retained. DTOs adapt backend
  snake_case and numeric IDs before presentation. Server status and receipt-age
  semantics remain authoritative; missing readings are not converted to zero,
  and phone connectivity failures are not reported as tank outages.
- Primary detail metadata errors fail the detail route. Secondary-source
  failures are independent unavailable states; resolved monitoring incidents
  are excluded. Live detail hides mock activity and equipment surfaces because
  no corresponding read API is used. No alert/equipment mutation is exposed.
- Directory/detail use load, error/retry, empty, pull-to-refresh, stale data,
  and one-minute app-resume refresh states; there is no background polling.

#### M4 — Read-only Alerts/Monitoring and Mark handled — 2026-09-25

- `ApiAlertRepository` shares the authenticated `ApiClient`. Water-quality
  active/history lists use `/alerts` and `/alerts/history?resolved=true`;
  because alert rows contain tank IDs but no tank names, one cached
  `/tanks?lifecycle=all` lookup enriches names without per-alert requests.
- Monitoring active/history uses `/monitoring-incidents` with the backend's
  paginated `state`, `page`, and `page_size` contract. The UI loads 25 per page
  and requests further pages on demand. Water-quality alerts and operational
  monitoring incidents remain separate streams; monitoring is never manually
  resolved from mobile.
- DTOs adapt snake_case fields, numeric IDs, UTC timestamps, nullable resolution
  data, backend resolution sources/reasons, and existing status vocabulary into
  mobile models. Dates are localized for display; backend lifecycle and
  reporting-recovery semantics remain authoritative. Alert detail is opened
  from the fetched record because the API has no standalone alert-detail route.
- Mark handled calls bodyless `PUT /alerts/{id}/resolve` after confirmation.
  The client submits once; after timeout, network, or server ambiguity it reads
  current alert state to reconcile and never blindly replays the mutation. The
  UI explicitly says handling removes the alert from the active queue and does
  not prove the water condition recovered. System resolution stays distinct
  from operator handling.
- Alerts and monitoring expose independent loading, empty, retry, partial-source
  error, pull-to-refresh, and stale-on-refresh behavior, plus refresh on resume
  when at least one minute old. There is no background polling. Alert and
  incident links from Home and Tank Detail route to the same live record.
  Alert detail stays open after handling and shows confirmed backend lifecycle
  and resolution metadata; Home and Alerts refresh when returning from detail.
  Failed deep-link loads remain retryable. No equipment or actuator command is
  exposed.

#### M5 — Account identity, Species, and read-only Equipment — 2026-09-25

- The existing authenticated user from `/auth/me` supplies Account name, email,
  backend role, and active status. The mobile `admin`/Owner presentation and
  `staff`/Staff presentation remain display mappings; no role or backend
  permission semantics changed. Profile editing and organization/customer
  account data remain unsupported because no such current-user contract exists.
- `ApiFishRepository` reads `/fish` and `/fish/{id}` through the shared
  authenticated client. DTOs map numeric IDs, snake_case fields, nullable
  ranges/text, category, diet, and guidance into the current species model.
  Category is not guessed to mean freshwater/saltwater, so live mode hides the
  mock-only water-type filters. Tank Detail opens the corresponding live
  species record while preserving its tank suitability context.
- `ApiEquipmentRepository` uses only GET requests: `/devices`, explicit-device
  actuator status, and page 1 of actuator history (10 records). It shows five
  known equipment types, state/schedule/connection/timestamps, and recent
  lifecycle history. Multiple registered devices require user selection.
  Backend `admin` alone can read device/actuator endpoints; Staff gets a local
  restriction explanation with zero requests. No command submission exists in
  the repository and no physical control is available in live UI.
- `succeeded` is presented as command lifecycle status and is not described as
  physical verification; `outcome_unknown` remains uncertain. Backend status
  GETs can reconcile overdue records. Older history pages, activity, and
  profile editing require separate product/API work.
- Species and equipment use mock repositories in tests and expose initial
  loading, retry/error, empty, partial/stale refresh, pull-to-refresh, and
  bounded resume refresh states without background polling.

### Mobile UI/UX refinement — 2026-09-15

- Reworked the authenticated shell to four destinations: Home, Tanks, Alerts,
  and More. Equipment is contextual to an Owner's tank and is not a top-level
  navigation destination; Staff receive a read-only equipment view.
- Refined the authenticated shell's bottom navigation into a safe-area-aware
  floating white dock with a restrained border, soft shadow, four custom
  destinations, and a mint selected capsule. Intentional vertical scrolling
  hides and restores the dock through translation only, so the page never
  resizes or snaps.
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

### Mobile startup refinement — 2026-09-23

- Replaced the looping aquarium loader with a pale underwater Flutter startup
  scene using the supplied illustration, existing AquaLogic mark, a restrained
  animated waterline, four ambient bubbles, and static `Preparing AquaLogic`
  text. No fake startup progress or looping fish movement is shown.
- Matched Android native and Flutter splash backgrounds and mark sizing, with a
  simple legacy launch background and light system bars. The Flutter scene
  remains until the minimum 600 ms visual window and auth destination resolve,
  then settles into the existing `AuthGate` destination.
- Reduced-motion startup disables bubbles and continuous waterline motion and
  uses opacity-only branding and handoff. Added focused splash readiness,
  timing, reduced-motion, and disposal tests.

### M6.1 Flutter FCM client foundation — 2026-09-26

- Firebase Messaging is initialized through an injectable app-level service;
  failures are contained so they do not block auth or the startup flow.
- Android notification permission is requested once per service lifecycle. The
  stable `aqualogic_alerts` channel uses the monochrome AquaLogic notification
  icon. Foreground FCM messages use local notifications; Android handles
  notification delivery in background/terminated states.
- The service keeps the FCM token and Firebase Installation ID in memory,
  emits each identifier's refresh changes separately, and does not log either
  value. It captures FCM/local notification-open payloads without adding
  navigation or backend registration in M6.1.
- Flutter analysis and all 172 tests pass; the release APK builds at
  `mobile_app/build/app/outputs/flutter-apk/app-release.apk` (63,434,355 bytes).
  A physical Android 12 device reported authorized notification access and
  obtained a 142-character FCM token; only a masked form appeared in debug
  output.
- A Firebase Console test message across foreground, background, terminated,
  and tap-launch states remains a manual verification step. No test message was
  sent during implementation.

### M6.2 Authenticated Android device registration — verified

- Added `PushDevice` and migration `0015_authenticated_push_devices`, with
  unique installation/token constraints and user/session foreign keys.
- `PUT /push/devices/current` derives the user and session from the validated
  JWT `sid`, accepts only Android, upserts the separate FID and FCM token, and
  safely rebinds one installation when the signed-in account changes. Its
  response omits both Firebase identifiers. Authenticated deactivation is
  session-scoped.
- Flutter stores a random installation UUID in Android secure storage, obtains
  the distinct Firebase Installation ID through FlutterFire, and coordinates
  registration after auth restore/login and FID/FCM availability or refresh.
  It performs best-effort deactivation before logout; registration and
  deactivation failures do not block authentication.
- Backend recipient eligibility excludes inactive devices/accounts, unsupported
  roles, and revoked or expired sessions. No Firebase sender or notification
  trigger was added in this milestone.
- Local M6.2 gates passed on 2026-09-26: backend full suite (161 passed),
  clean SQLite upgrade to Alembic head `0015`, Flutter full suite (180 passed),
  `flutter analyze` (no issues), release APK build, and `git diff --check`.
  A local PostgreSQL integration migration check was not available in this
  environment.
- Railway `/health` is healthy, OpenAPI exposes both registration routes, and
  the response schema omits both Firebase identifiers. A human-confirmed Railway PostgreSQL
  query on 2026-09-26 showed one recent, active Android row with a non-null auth
  session. The query did not select the FCM token; M6.2's physical registration
  gate is complete.

### M6.3 FID-compatible Firebase Admin sender and notification outbox — deployed and verified

- Added the official Firebase Admin Python SDK behind a lazy sender boundary.
  It targets `messaging.Message(fid=...)` only after the Android client confirms
  FCM registration for that FID; otherwise it uses a retained FCM token for
  compatibility. Push defaults
  off; credentials are decoded only in memory from
  `FIREBASE_SERVICE_ACCOUNT_JSON_B64`, and sanitized errors never include SDK
  exception text, service-account material, FIDs, or FCM tokens.
- Migration `0016_push_notification_outbox` adds unique logical event keys and
  one-per-event/device delivery rows. Migration
  `0017_push_device_firebase_installation_id` adds a nullable unique FID column;
  deployed migration `0015` and its existing production row are preserved.
  Enqueueing stays inside the caller's transaction; a separate dispatcher uses
  database leases, immediate recipient/session rechecks, bounded retry, and
  matching-recipient deactivation.
- Automated tests use a fake sender and SDK stubs; no live Firebase request is
  made. Alert and monitoring event triggers remain gated to M6.5.
- A first controlled production test on commit `61138e7` was definitively
  rejected as an unregistered recipient. The matching device was deactivated
  under the existing invalid-recipient policy. Safe status checks confirmed
  one failed delivery, an active/unrevoked session at send time, and no stored
  Firebase message ID; no FID or FCM token was queried. This showed that the
  earlier client had fetched an FID without completing FCM's FID registration.
- The correction adds migration `0018_push_device_fid_registration`, which
  marks pre-existing rows as not FID-registered and allows an FCM token to be
  absent for FID-only clients. Android now enables Firebase's FID mode and
  awaits `FirebaseMessaging.register()` through a small native bridge before
  FlutterFire reads or publishes the FID. `FirebaseInstallations.onIdChange`
  repeats that registration flow. The sender uses FID targeting only when the
  explicit registration marker is true; older clients retain token fallback.
  Migration `0015` is unchanged.
- Automated sender tests verify FID targeting only for registered FIDs, legacy
  token fallback, registration and FID changes, idempotent upsert, and
  response/log redaction. They use fake senders; no live Firebase message is
  sent.
- Production M6.3 checks passed on 2026-09-26 for commit
  `61138e703b02ff656469546b970e88502601edfc`: Railway
  deployment succeeded, `/health` returned 200, Alembic reported head `0017`,
  and OpenAPI exposed both registration routes with the FID only in the request
  schema. The response schema omits both Firebase identifiers. With the human-
  enabled push flag true, runtime startup logs contained no Firebase
  configuration pause; a sanitized log scan found no credential markers or
  long token-like values. Two active admin Android rows had a current bound
  session and FID; the query selected only registration booleans and timestamps.
- The FID-registration correction's local gates passed: backend full suite
  (199 passed), Flutter full suite (184 passed), `flutter analyze` (no issues),
  isolated SQLite upgrade to Alembic head `0018`, and release APK build
  (`mobile_app/build/app/outputs/flutter-apk/app-release.apk`). The only backend
  warning is the expected deprecation warning on the retained token fallback.
- The Firebase credential was provisioned directly through Railway and is not
  in the repository. The FID-registration correction was published in commit
  `ca1468c6b8a03c964686dd6c821e0992f02c8a55`; Railway deployed it, `/health`
  remained healthy, migration `0018` reached head, and production OpenAPI and
  startup checks passed. Sanitized log review found no Firebase credential or
  identifier values.

### M6.4 Railway → physical Android test — complete

- Production verification returned only the requested booleans:
  `active=true`, `session_bound=true`, and `fid_registered=true`.
- One controlled M6.4 test notification was sent through the deployed Firebase
  Admin sender. The backend marked its delivery `sent`, and the human confirmed
  that it appeared on the physical Android phone. No FCM token or FID was
  queried or exposed.

### M6.5 Alert and monitoring event triggers — deployed and healthy

- New Alert creation enqueues `water_quality_alert:{alert_id}:created` in the
  source transaction. Existing active Alerts do not enqueue again when readings
  repeat or severity changes; water-quality resolution does not enqueue. A new
  Alert after resolution receives its own event.
- New MonitoringIncident creation enqueues one `monitoring_incident:{id}:opened`
  event. Only a successful `reporting_recovered` transition enqueues
  `monitoring_incident:{id}:recovered`; `monitoring_disabled` and `tank_retired`
  do not.
- The existing unique event key and per-device constraints remain the duplicate
  barriers. Recipients are materialized when the source event is enqueued, so a
  later device registration does not receive an old event. Firebase network
  work remains in the independent dispatcher.
- Backend full suite: 209 passed. Focused push/monitoring suite: 56 passed.
  A clean isolated SQLite migration reached `0018_push_device_fid_registration`
  (head); no schema change was needed for M6.5. The only warning is the
  intentional deprecated-token fallback used for legacy rows.
- Commit `4a693ae` is deployed from `main` to Railway production. The pre-deploy
  Alembic command succeeded and a direct production check confirmed
  `0018_push_device_fid_registration` is at head. `/health` returned 200/`ok`,
  and production OpenAPI exposes `/push/devices/current` and
  `/push/devices/current/{installation_id}`. Sanitized runtime-log and response
  checks found no Firebase credential, FID, or FCM-token values. No production
  sensor, threshold, or hardware state was changed.

### M6.6 authenticated notification navigation — deployed; physical taps pending

- Firebase initial opens, `onMessageOpenedApp`, and foreground local-notification
  taps now enter one navigation coordinator. Version 1 payloads are validated
  as string-only records with positive IDs and matching deterministic event
  keys; notification titles, bodies, and claimed alert state are not treated as
  authoritative.
- The coordinator retains one pending tap through auth restoration, login, and
  required password change, then waits for the authenticated shell. A bounded
  in-memory event/message deduplicator prevents repeated navigation. Unknown or
  malformed messages use the neutral Alerts fallback without opening protected
  records while signed out.
- The existing authenticated Alerts repository fetches current Alert state and
  opens Alert Detail, including resolved history. Monitoring outage and
  recovery notifications search the existing active/history incident streams;
  missing records and request failures keep their existing neutral/retry UI.
- Flutter full suite: 198 passed. `flutter analyze` reported no issues, and the
  release APK built at
  `mobile_app/build/app/outputs/flutter-apk/app-release.apk` (60.7 MB). No live
  notification was sent as part of local verification.
- The M6.6 client changes are included in the deployed release. Install this
  APK and complete physical Alert, monitoring outage, and recovery tap checks
  with the app foregrounded, backgrounded, and swiped away before considering
  M6.6 complete. No additional notification was sent during release checks.

Home, the Tanks directory/detail, and Alerts/Monitoring are connected to live
read-only API data. Separate sensor-history charts, activity, profile editing,
real actuator commands/device connectivity, command reconciliation, and
production equipment safety controls are not integrated in the Flutter client.
M6.2 authenticated device registration and M6.3 sender health are verified in
production. M6.4's physical registration and one-notification receipt gate has
passed. M6.5 event triggers are deployed and pass the local backend suite.
M6.6 navigation is deployed and passes Flutter tests/build; physical Android
tap verification remains pending.

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
- Assess whether users need older actuator-history pages, and define a
  supported backend contract before adding account editing, organization
  profile, or recent-activity features.
- Finalize deployment environment variables and production smoke tests.

## Planned

- External monitoring notifications, delivery workers, and escalation remain
  deferred.
- Account editing, organization/customer profile data, recent activity, and
  older equipment-history pages are not currently in the mobile API slice.
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
- SQLite is the normal local database; a live PostgreSQL migration check remains
  pending because the available local PostgreSQL service did not accept the
  available local role credentials.
- Dashboard list endpoints do not yet paginate.
- Fleet analytics stream required reading columns and aggregate them in the
  application; custom windows are therefore capped at 30 days and 1,000
  buckets.
- The current public API exposes the latest configured sensor values; this needs
  a final privacy and threat review before production.
- Flutter is directly connected to Railway for authentication, Home, Tanks,
  Alerts, Monitoring, Species, and read-only Equipment. Activity, account
  editing, organization profile, and sensor history remain outside the live API
  slice.
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

## Validation checkpoint — 2026-09-25 (M4 Alerts/Monitoring)

- Targeted API repository and mutation-reconciliation tests passed; the full
  Flutter suite passed all 146 tests. `flutter analyze --no-pub` found no
  issues, and targeted Dart formatting reported no formatting changes.
- `flutter build apk --release` succeeded. The APK is 61,747,891 bytes at
  `mobile_app/build/app/outputs/flutter-apk/app-release.apk`.
- API repository tests use fake HTTP responses. The only production request was
  the non-mutating `GET /health` check (HTTP 200); no authenticated production
  request, alert mutation, actuator command, or device install was run.

## Validation checkpoint — 2026-09-25 (M5 Species/Equipment)

- `flutter pub get` succeeded. `dart format --set-exit-if-changed` passed for 23
  changed/new Dart files with no formatting changes; `flutter analyze --no-pub`
  found no issues; `flutter test --no-pub --reporter expanded` passed all 159
  tests.
- `flutter build apk --release` succeeded in 172.3 seconds. The APK is
  62,338,099 bytes (59.5 MiB) at
  `mobile_app/build/app/outputs/flutter-apk/app-release.apk`.
- `git diff --check` passed. API tests use fake HTTP responses; no production
  Railway request, actuator command, or device install was run.

## Validation checkpoint — 2026-09-25 (M3 Tanks)

- Mobile M3: `flutter pub get` succeeded; `dart format` reported 0 unformatted
  changes across the touched Dart files; `flutter analyze` found no issues;
  `flutter test --reporter expanded` passed all 108 tests, including Tanks
  loading/filter/retry/refresh, partial reading, offline, species, partial
  source failure, 404, and live navigation coverage.
- `flutter build apk --release` succeeded in 178.3 seconds. The APK is
  61,402,275 bytes (58.6 MiB) at
  `mobile_app/build/app/outputs/flutter-apk/app-release.apk`.
- `git diff --check` passed. Repository tests use fake HTTP responses; no
  authenticated production API request, mutation, or device install was run.

## Validation checkpoint — 2026-09-25 (M2 Home)

- Mobile M2 Home: `flutter pub get`, changed/new-file `dart format`,
  `flutter analyze` (no issues), and `flutter test --reporter expanded`
  (83 passed) succeeded. `flutter build apk --release` succeeded; the current
  APK is 61,320,355 bytes (58.5 MiB). `git diff --check` passed.
- API repository tests use fake HTTP responses. No authenticated production
  API requests or mutations were made. The APK path is
  `mobile_app/build/app/outputs/flutter-apk/app-release.apk`.

## Validation checkpoint — 2026-09-25 (M1)

- Mobile M1: `flutter pub get`, changed-file `dart format` check,
  `flutter analyze` (no issues), and `flutter test` (70 passed) succeeded.
  `flutter build apk --release` succeeded; the APK is 60,959,907 bytes
  (58.1 MiB). Inspection of the packaged manifest confirmed the INTERNET
  permission and `android:usesCleartextTraffic="false"` for release.
- Authentication tests use fake HTTP and in-memory secure storage; no
  production login credentials or live auth requests were used. A human
  credential smoke test remains available in the M1 handoff instructions.

## Validation checkpoint — 2026-09-23

- `python -m pip install -r requirements.txt` succeeded and installed
  `psycopg2-binary 2.9.13`; configuration tests cover development SQLite
  defaults, production rejection of a missing or SQLite URL, accepted
  PostgreSQL URL forms, and Alembic percent-encoded credential round-tripping.
- Backend baseline was 126 passed and 3 failed. The failures were test setup
  issues: the restore fixture used the latest model schema but stamped it as
  revision `0008`; the analytics threshold-history test had no tank in scope;
  and the disabled-threshold test changed the ORM row directly without writing
  the history revision that production reads use. The fixtures now use a real
  revision-`0008` migration, create an active tank for analytics scope, and
  disable the threshold through its API. Assertions were preserved.
- Final backend suite: `python -m pytest -q` passed with 137 tests, including a
  migration-version-capacity regression check.
- A clean temporary SQLite database upgraded from revision `0001` through head;
  a second `alembic upgrade head` ran with no migration work. FastAPI started
  against temporary file-backed SQLite and `/health` returned HTTP 200.
- The Railway PostgreSQL error exposed revision `0013`'s 36-character ID
  exceeding Alembic's default `VARCHAR(32)` version column. Migration `0012`
  now widens that column to `VARCHAR(64)` on PostgreSQL before Alembic records
  the next revision; SQLite skips the alteration. A scan found no other
  revision IDs over 32 characters.
- A PostgreSQL 18 service was running locally and port 5432 responded, but no
  available local role could authenticate. No PostgreSQL database was created;
  the new version-column alteration and full PostgreSQL migration chain still
  need verification with an authorized test database.

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

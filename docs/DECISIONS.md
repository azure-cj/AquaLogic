# AquaLogic Architecture Decisions

Status: Living decision log
Last reviewed: 2026-09-25

Record choices that affect multiple components or future work. Small local
implementation choices belong in code and tests; do not turn this into a diary.

## 2026-09-25 — Use native secure refresh storage for Flutter auth

**Decision:** The production Flutter composition calls the Railway FastAPI root
directly. `ApiClient` keeps access JWTs in memory, refreshes from the
backend-provided `expires_at` and after one 401, and serializes concurrent
refresh attempts. The client stores only the opaque `aqualogic_refresh` cookie
value in platform secure storage and sends it only to `/auth/refresh`. Release
builds default to Railway and require HTTPS; debug Android manifests alone
permit local HTTP development. `MockAuthService` and existing feature mocks
remain injectable and available.

**Reason:** Native Flutter is not governed by the browser's same-origin proxy,
SameSite, or CORS behavior. Keeping a single native auth transport reuses the
existing bearer/rotating-session backend without persisting JWTs or adding a
second auth system. Preserving mock injection keeps widget tests deterministic
while the operational repositories are integrated in later milestones.

**Consequences:** No FastAPI, Railway, or Vercel change is required for M1.
Cold start validates the refresh session and hydrates `/auth/me`; network
unavailability preserves the refresh credential and offers retry. Physical
equipment controls and operational data remain outside this milestone.

## 2026-09-25 — Connect Flutter Home through the existing API boundary

**Decision:** M2 Home uses the shared authenticated `ApiClient` through an
`ApiHomeRepository`, reading `/fleet`, active `/alerts`, and the first page of
active `/monitoring-incidents`. Keep `MockHomeRepository` injectable. Use the
server's fleet status and reporting age, and the paginated incident total;
omit recent activity until an existing backend source supports it. Preserve
partial fleet data when either secondary Home source fails, and never route a
real backend ID into a mock detail screen.

**Reason:** The existing endpoints already provide role-authorized Home
summaries, and their status, receipt-age, and monitoring semantics are
authoritative. A new aggregate route or duplicate client freshness logic would
create unnecessary compatibility and consistency risk.

**Consequences:** Home is live while Tanks, Alerts/Monitoring detail, and other
operational features remain mock-backed until their own milestones. Network
failure stays distinct from tank/device Offline, water-quality alerts stay
distinct from monitoring incidents, and no mutation or physical control is
introduced by this integration.

## 2026-09-23 — Require PostgreSQL for production and retain SQLite locally

**Decision:** Keep SQLite as the backend default for local development and
tests. When `ENVIRONMENT=production`, require a valid PostgreSQL `DATABASE_URL`
and fail startup on a missing, malformed, or SQLite URL. Use synchronous
SQLAlchemy with `psycopg2-binary`; normalize the common `postgres://` alias and
escape percent signs only while passing the URL through Alembic's
ConfigParser-backed settings.

**Reason:** Railway PostgreSQL should run the existing synchronous backend and
shared migration history without changing local development or introducing a
production fallback to a local SQLite file.

**Consequences:** Migrations that alter referenced tables use native PostgreSQL
operations while retaining SQLite batch operations. The clean SQLite migration
chain is validated locally; a full PostgreSQL upgrade remains pending until a
usable local PostgreSQL role or the production database is available.

## 2026-09-23 — Keep global defaults with complete optional tank overrides

**Decision:** Keep `ThresholdConfig` as the global fallback and allow an
administrator to save a complete per-parameter override for an active tank.
An override replaces the full bound set and enabled state, uses the parameter's
fixed unit, and can be reset so the tank follows future global revisions.
Record every override and reset in append-only tank history. Evaluate readings,
alerts, statuses, public projections, and analytics through one effective
threshold resolver. A multi-tank analytics view draws shared threshold bands
only when all included effective histories match.

**Reason:** Tanks may need different operational limits, while the confirmed
global defaults remain useful for newly created and unconfigured tanks. Deriving
limits from fish preferences would silently impose one species' care range on a
mixed tank and would conflate advisory species care with operational monitoring.

**Consequences:** All tanks continue to inherit existing global values until an
administrator configures an override. Reset history explicitly returns to the
global timeline, while existing readings and alerts remain intact. Public pages
continue to expose operational statuses without threshold values.

## 2026-09-17 — ESP32 bridge drains the offline backlog with ack-after-confirmation

**Decision:** The temporary ESP32 bridge now drains the sensor backlog the
firmware records to flash while offline. On every successful live `/data` poll
it calls `GET /data/backlog/count`; when `pending > 0` it pulls batches of 50
records (`GET /data/backlog?limit=50`), forwards each record to the existing
`POST /device-ingestion/readings` endpoint with the same `X-Device-Key`
auth, and only then acks on the device (`POST /data/backlog/ack?upto=seq`)
after the backend confirms each batch. Drain is capped at 500 records per poll
cycle and is skipped entirely when the live poll fails.

**Reason:** The live-only bridge dropped every reading taken while the ESP32
was offline between bridge polls or WiFi outages. Draining is additive per
cycle, reuses the existing live-forwarding endpoint/auth/field mapping, and
never blocks the normal polling cadence.

**Consequences:** A backward-forward failure mid-batch acks only the already
confirmed prefix, so acked records are never re-sent (no duplicates) and
unacked records stay on the device for the next cycle (no loss — the ESP32
re-returns them until acked). Drain failures are logged and never crash the
process or disturb live polling. The ack endpoint is the only new device call;
no backend endpoint was added or changed. Confirmed upstream in
`bridge/esp32_bridge.py` and `bridge/tests/test_esp32_bridge.py`.

## 2026-09-17 — Backlogged ESP32 readings get an estimated observed_at in the bridge

**Decision:** Backfilled readings no longer share the drain time as
`observed_at` (the previous behavior stamped every backlogged record at the
moment it was forwarded, wrong by up to the full outage duration). The bridge
now estimates each record's sample time by spreading records evenly over
`[last clean live reading, now]` in `seq` order. The anchor is frozen while the
backlog is non-empty so the window does not drift across multi-cycle drains,
and it resets to `None` on bridge restart, in which case the window falls back
to `now - pending * poll_interval_seconds`. Estimates are marked
`time_estimated=true` / `estimation_method="even_spread"` on the internal
payload and in the drain log line; the marker keys are stripped before posting
because the backend schema forbids unknown fields today.

**Reason:** The ESP32 has no real-time clock (no RTC/NTP in scope), so true
sample times are unknowable; a deterministic, monotonic best-guess is strictly
better than stamping everything with drain time (which corrupts ordering and
interval-based dashboards/reporting).

**Consequences:** Live `/data` forwarding is unchanged. A reboot mid-outage
produces a seq jump; estimation still yields bounded, non-future timestamps and
never crashes. The estimation flag is not yet persisted on
`backend/app/schemas/sensor.py` (`SensorReadingCreate` uses `extra="forbid"`, so
markers must stay off the wire). Follow-up: add `time_estimated` (and optionally
`estimation_method`) to `DeviceReadingCreate` / the `SensorReading` model with
an Alembic migration, wire it through `ingest_device_reading` in
`backend/app/routes/devices.py`, expose it in `SensorReadingRead`, then re-enable
sending the markers from the bridge. Confirmed upstream in
`bridge/esp32_bridge.py:815-924` and `bridge/tests/test_esp32_bridge.py`.

## 2026-09-15 — Use a translating overlay for mobile bottom navigation

**Decision:** Keep the authenticated mobile shell's four destinations—Home,
Tanks, Alerts, and More—in a custom soft floating dock over the page. Hide and
restore it with translation after cumulative vertical scroll thresholds rather
than changing the Scaffold or page layout height.

**Reason:** A floating dock gives the mobile dashboard a calmer, more
integrated control surface while allowing users to expose content beneath it.
Transform-only motion preserves scroll position and viewport constraints,
which prevents the snapping caused by animating an attached navigation bar's
height.

**Consequences:** The dock must remain mounted, safe-area aware, excluded from
hit testing while hidden, and visible at the top of a page and after tab
selection. Shared page padding stays modest; it must not become a permanent
navigation spacer.

## 2026-08-21 — Preserve retired tank history outside live operations

**Decision:** Add a bounded `Active -> Retired` tank lifecycle after the core
final-hardening fixes. Retired tanks leave live fleet, public, monitoring, and
equipment-control workflows while retaining their readings, alerts, species
assignments, device/command history, configuration, and owned media for
authorized historical review. Permanent deletion remains separate and requires
retirement first. Reactivation is deferred.

**Reason:** Hard deletion is relationally consistent but irreversibly removes
operational evidence that remains useful when a physical tank is taken out of
service. A two-state lifecycle retains that evidence without introducing a
general asset-management system.

**Consequences:** Implementation requires an Alembic migration, dedicated
administrator lifecycle endpoint, active/retired query behavior, write/control
guards, public-page shutdown, device deactivation, UI history access, and new
regression coverage. This is project-owner direction and is not represented as
a direct quote or recorded answer from JRed.

## 2026-08-21 — Persist unattended tank-level monitoring outages in-app

**Decision:** Add one persistent monitoring-outage incident per eligible active
tank after a configurable grace period that defaults to 15 minutes without a
fresh accepted reading. Keep the existing 90-second request-time Offline rule.
A fresh accepted reading automatically resolves the incident. Delivery remains
in-app only.

**Reason:** Request-time Offline status protects against showing stale Normal
data but cannot record an overnight outage while nobody uses the dashboard. A
tank-level incident matches the operational question even when a tank has
multiple registered devices and avoids creating duplicate device alarms.

**Consequences:** Implementation requires explicit monitoring-expectation
eligibility, an idempotent background detector, a dedicated persistence/API/UI
contract, recovery integration in reading ingestion, and retirement/device
lifecycle handling. Push, email, SMS, on-call routing, and enterprise
observability remain deferred. This is project-owner direction and is not
represented as a direct quote or recorded answer from JRed.

## 2026-08-22 — Implement bounded persistent monitoring incidents

**Decision:** Implement the 2026-08-21 monitoring decision as a dedicated
`MonitoringIncident` model and in-app API/UI slice. Use a tank-level detector
with a 900-second default grace period, one active row per eligible active tank,
idempotent recovery on accepted readings, and explicit `monitoring_disabled` or
`tank_retired` terminal reasons. Preserve the 90-second request-time Offline
rule and analytics reporting-gap reconstruction as separate concerns.

**Reason:** The approved scope is now sufficiently specified to ship without
introducing external notification delivery, generalized scheduling, or an
enterprise job system. Database uniqueness and writer serialization make
multiple detector workers safe for SQLite development and PostgreSQL deployment.

**Consequences:** Migration `0013_persistent_monitoring_incidents` must be
applied before workers start. Deployment validation must still exercise restart,
late accepted readings, and PostgreSQL locking with the safe operational
checklist.

## 2026-08-21 — Leave fish compatibility undecided and notes-only

**Decision:** Do not choose or implement a fish-to-fish compatibility model in
the final hardening pass. Preserve free-text compatibility notes and the current
water-only Species Care evaluator until the project owner supplies a later
direction.

**Reason:** A reliable compatibility workflow needs a deliberately curated
knowledge model and ownership process. Selecting one prematurely would create
unsupported biological claims and expand scope beyond the approved hardening
work.

**Consequences:** No pairwise scores, assignment blocking, structured
compatibility rules, or new compatibility statuses may enter the implementation
plan. UI clarity work may explain the current limitation without filling it.

## 2026-07-27 — Use layered project context

**Decision:** Keep `AGENTS.md` as a short operating guide and use focused
canonical documents under `docs/` for product context, architecture, contracts,
status, and workflows.

**Reason:** A single large context file becomes difficult to keep current and
causes agents to load irrelevant history. The index lets an agent select the
smallest useful context set.

## 2026-07-27 — Treat the nested `AquaLogic` directory as the repository root

**Decision:** Place agent instructions and canonical documentation in the
nested directory that contains `.git`, `backend`, `web`, `mobile_app`, and
`docs`.

**Reason:** That is the actual Git root and is the stable boundary for source,
tests, and documentation. The parent folder is only a workspace container.

## 2026-07-27 — Keep software-first, local-first development

**Decision:** Develop and validate backend, web, mobile prototype, and seeded
data before making hardware integration a prerequisite.

**Reason:** The system can demonstrate operational value and stabilize its data
contract before sensors and actuators are available.

## 2026-07-27 — Use the current source as the implementation authority

**Decision:** The route modules, schemas, models, migrations, tests, and current
web/mobile source override earlier plans when they disagree.

**Reason:** The repository has accumulated proposal documents and implementation
reports from different phases. The documentation index labels those documents
without deleting useful historical context.

## 2026-07-27 â€” Make admin navigation adaptive from one grouped config

**Decision:** Define Monitor, Manage, and Configure navigation groups once and
render their items flat until more than eight configured pages exist. At
desktop widths below 1200px, or above that page limit, render the same groups
as click-toggle dropdowns; retain the mobile drawer below 820px.

**Reason:** The navigation can grow without duplicating route definitions or
adding width measurement logic, while preserving the current wide-screen
experience.

**Consequences:** Adding a ninth configured page switches desktop navigation
to clusters for every role. Page-specific actions, including Add tank, stay in
their relevant page headers.

## 2026-07-27 — Make the fish directory grouped by default

**Decision:** Present fish species in collapsible care groups by default and
provide a remembered compact-list view. Store diet category separately from
free-form feeding details, expose tank usage counts, and reject deletion while
a species is assigned.

**Reason:** Grouping keeps a growing species catalog navigable, while the
compact alternative supports staff who prioritize dense operational scanning.
Structured diet and usage data make both views scannable and ensure deletion
protection is enforced by the API rather than only implied by the interface.

**Consequences:** Fish species now have `category` and `diet_type` fields, the
list contract includes `tank_count`, and existing databases require migration
`0004_fish_species_directory`.

## 2026-07-27 — Preserve operational context in fleet analytics

**Decision:** Keep fleet average as the default analytics scope, permit up to
three tank overlays, version threshold changes append-only, represent missing
buckets as nulls, and align different-unit parameter comparisons in separate
charts. Persist view state in the URL and export the visible dataset as CSV.

**Reason:** Operators need to identify which tank caused a fleet movement,
interpret readings against the rules active at that time, and distinguish
missing reports from zero values without creating misleading dual-axis charts.

**Consequences:** Analytics requests are capped at 30 days and 1,000 buckets,
threshold updates create revision records, and existing thresholds are
backfilled from the earliest known reading because earlier configuration
history cannot be reconstructed.

## 2026-07-28 â€” Keep species-care suitability derived and separate from alerts

**Decision:** Evaluate assigned species against a tank's latest fresh reading
on an authenticated read endpoint, with `suitable`, `attention`, and
`unavailable` results. Do not persist a species-care status or create Alert
records in this phase.

**Reason:** Species preferences are ideal ranges, not operational critical
boundaries. Dynamic evaluation reflects new readings, assignments, and range
edits immediately without derived-state synchronization or collisions with the
existing unresolved `tank_id + parameter` alert deduplication.

**Consequences:** The staff drawer owns a separate care presentation and polls
the endpoint while open. Future persistent care alerts require a category or
source, fish-species identity, a stable unresolved key, and resolution rules.

## 2026-07-28 — Dedicated staff tank workspace

**Decision:** Keep `/admin/tanks` as the configuration directory and make
`/admin/tanks/:tankId` the authenticated workspace for live operations,
Species Care, assignments, and operational alert resolution. Reuse one
configuration-only drawer from either route.

**Reason:** Operators need a bookmarkable context for one installation without
duplicating live concerns in a scanning-oriented directory.

**Consequences:** Species Care remains dynamic and distinct from operational
alerts. The detail route independently polls operations and suitability, so
their timestamps can briefly differ while sensor ingestion is in flight.

## 2026-07-29 â€” Use database-backed rotating refresh sessions

**Decision:** Issue 15-minute HS256 access JWTs only to browser memory and use
one seven-day opaque refresh token in a Strict, HttpOnly cookie. Persist only
SHA-256 refresh/setup-token hashes, active session state, user token versions,
and audit metadata.

**Reason:** A leaked access token has a short lifetime, while rotation and
session checks make sign-out, password reset, replay detection, and account
disablement immediately enforceable without browser token storage.

**Consequences:** Deployment intentionally invalidates all legacy JWTs. The
web client must bootstrap with refresh, coordinate sign-out across tabs, and
never persist authorization material. Setup links are administrator-mediated
30-minute fragments rather than temporary passwords.

## 2026-08-14 — Use a laptop bridge with fixed server-side tank mapping

**Decision:** Keep the received ESP32 firmware unchanged and use a temporary
local-laptop bridge that polls only `/data`. Authenticate the bridge with a
hash-stored device key that resolves to one registered tank; accept only the
four installed measurements.

**Reason:** The ESP32 is on the tester's LAN and must not be public or receive
staff credentials. Fixed mapping prevents a compromised bridge from selecting
another tank. Missing dissolved oxygen and ammonia are unknown, not safe zeroes.

**Consequences:** The device-provisioning response shows the raw key once,
bridge retries must tolerate tunnel outages, and dashboard statuses mark the
two deferred metrics unavailable. Direct ESP32 posting and all commands remain
deferred.

## 2026-08-15 — Route v1 actuator control through a claiming laptop bridge

**Decision:** Keep the received ESP32 firmware unchanged and route admin-only UV,
normal LED, and feeder commands from the backend to the existing tester-laptop
bridge. The bridge claims each expiring server command before making one exact
local firmware request, then reports the result and validated local state with
the registered device key.

**Reason:** The ESP32 remains private on the tester's Wi-Fi, while the backend
retains authentication, fixed device-to-tank ownership, payload validation,
auditability, expiry, and duplicate-delivery protection. A one-shot hardware
request avoids repeating a physical action after a timeout whose execution is
unknown.

**Consequences:** Actuator state is last-known and becomes stale when the
bridge is offline; command status and state history require new migration
`0008_actuator_controls`; staff has no actuator API access; syringe pumps and
pH auto-dose remain out of scope. Dashboard/API tunnels are temporary test
infrastructure and must never include an ESP32 tunnel.

## 2026-08-15 — Add a guarded Pump A/B manual-test bridge phase

**Decision:** Extend the generic actuator command ledger for `pump_a` and
`pump_b`, but expose only admin-confirmed `dispense`, `stop`, and `retract`
manual tests. The bridge keeps `pump_manual_test_enabled` false by default,
requires a fresh fixed-device heartbeat before pump commands are queued, and
uses a 100–2,000 ms local dispense cutoff. Because the received firmware's
dispense route has no duration parameter, the bridge sends the exact dispense
route once and then one intentional matching stop request after the cutoff.

**Reason:** This permits controlled empty-syringe/water mechanical checks
without changing firmware, pins, wiring, or Wi-Fi behavior and without creating
an automatic dosing path. The existing JSON command/state tables already store
the validated pump payload and audit lifecycle, so no new migration is needed.

**Consequences:** Pump schedules, pH auto-dose, sensor-driven dosing, and
public ESP32 access remain excluded. A physical timeout or ambiguous response
is reported as failed and never retried automatically; the tester must use the
visible Stop control or inspect the hardware locally.

## 2026-08-17 — Execute pump doses by firmware-configured volume

**Decision:** Replace the dashboard and backend pump millisecond cutoff payload
with an empty `dispense` payload. The bridge reads both pump statuses, refuses
to start while either pump is active, triggers the selected firmware dispense
route once, and polls its status until the configured `volume_ml` move reports
complete. A bounded bridge timeout may issue one intentional safety stop.

**Reason:** The current calibrated firmware computes the step target from its
internal `syringe*DispenseML` and `syringe*StepsPerML` values, but its dispense
routes accept no query parameter. A millisecond value therefore measures bridge
runtime rather than the configured volume and cannot be presented as an exact
mL dose.

**Consequences:** The UI can show and execute the firmware-reported configured
volume, but cannot edit it yet. Adding editable mL configuration requires a
separately approved firmware endpoint and persistence review. Pump tests remain
empty-syringe/water-only, default-off, admin-only, and never automatically
retry a physical dispense.

## 2026-08-17 — Focus the tank editor and add safe hero imagery

**Decision:** Keep tank create/edit centered on operational identity and public
QR-page content. Support an allowlisted HTTPS hero-image URL and an admin-only
JPG/PNG/WebP upload for existing tanks, with a 5 MB limit and an application
media path. Do not expose customer assignment in the demo-facing form while
that workflow is being redesigned.

**Reason:** The previous drawer mixed internal relationship management with
public presentation fields and offered no image preview or upload path. A
focused form is easier to use in the demo while preserving customer ownership
in the backend contract.

**Consequences:** Local disk uploads work for the local-first demo, but durable
production uploads require a persistent volume or an object-storage adapter.
New tanks use a URL at creation and can receive an uploaded hero image after
the first save.

## 2026-08-17 — Make species care requirements editable and understandable

**Decision:** Keep species preference ranges in the existing fish profile
contract and expose supported temperature, pH, and TDS ranges through the
authenticated directory editor and details view. Add explicit care-group,
diet, and tank-usage filters, safe assigned-tank summaries, and clearer
Species Care status/freshness wording.

**Reason:** FR-11 requires fish care information and ideal water conditions;
FR-12 requires searchable and filterable species data; and FR-13 requires
suitability guidance based on current tank readings. The backend already stores
the preference ranges, so this closes the web usability gap without a schema
change or reintroducing deferred ammonia/dissolved-oxygen UI.

**Consequences:** Authenticated fish directory responses include only tank IDs
and names for assignment summaries. Public fish responses remain privacy-safe
and unchanged. Species Care remains derived, not an alert lifecycle.

## 2026-08-18 — Align fish photos with tank media management

**Decision:** Keep hosted species-photo URLs supported and add an admin-only
JPG/PNG/WebP upload endpoint that stores local files under the application media
path. The fish editor previews either source and allows uploaded photos to
replace the current image.

**Reason:** Fish species management needs the same practical image workflow as
tank management, while local uploads keep the demo independent of third-party
image hosting and preserve the existing `photo_url` contract.

**Consequences:** Existing species do not require a schema migration. New local
uploads use a separate 5 MB limit setting, `MAX_FISH_IMAGE_BYTES`, and durable
production storage still requires a persistent volume or object-storage adapter.

## 2026-08-21 — Use paired isolated local recovery bundles

**Decision:** Package file-backed SQLite and `MEDIA_ROOT` together in a
versioned, checksummed backup bundle. Restore only into a new isolated target;
the restore process applies Alembic migrations, runs SQLite integrity checks,
revokes every restored session, and increments every restored user's token
version. Keep production PostgreSQL backup and point-in-time recovery
provider-managed, with media retention planned alongside the database policy.
Enable SQLite foreign keys in both application and test engines.

**Reason:** Database-only recovery can leave image references broken, while
live replacement risks destructive downtime and restored sessions can revive
stale access. SQLite must enforce the same relationship behavior that the
application expects from PostgreSQL. Provider-native PostgreSQL recovery is
deployment infrastructure and should not be duplicated in application code.

**Consequences:** Operators use `scripts.backup_local` and
`scripts.restore_local`; there is no live-restore flag or HTTP recovery
endpoint. Local bundles contain operational data and must remain outside Git
and under restricted access. Production RPO, RTO, retention, encryption, and
media-storage decisions remain deployment responsibilities.

## 2026-08-21 — Make account administration a lifecycle workspace

**Decision:** Keep the two-role model and derive account lifecycle metadata from
existing users, sessions, and audit events. Give administrators a staff detail
workspace with sanitized session inspection, confirmation-gated lifecycle
actions, and filtered per-user audit activity. Keep staff on the personal
Account Center and Security surfaces only; administrator session revocation may
not target the administrator's own account.

**Reason:** Account administration needs to explain access and security context,
not only expose destructive buttons. Derived data avoids a migration while
session and audit boundaries remain explicit and enforceable on the backend.

**Consequences:** The administrator user response gains additive derived fields
and three administrator-only session endpoints. The web client has richer
account and staff workspaces, but custom permissions, departments, shifts,
tank ownership, and customer accounts remain out of scope.

## 2026-08-21 — Harden the Phase 01 domain foundation without narrowing device topology

**Decision:** Keep multiple active devices per tank for the current release, but
add administrator device lifecycle controls for inspection, activation,
deactivation, and one-time key rotation. Record a nullable source device and a
server-side receipt timestamp on sensor readings. Derive device connection state
from activation and last-seen time. Keep dissolved oxygen and ammonia as nullable
compatibility fields while hiding them from current bridge and user-facing
workflows.

**Reason:** The current bridge and actuator boundary already support fixed
device-to-tank mappings, and a one-device constraint may change as the hardware
topology evolves. Reading provenance and server receipt time are needed for
traceability and freshness without forcing a separate per-parameter model.

**Consequences:** Phase 01 now includes a backend and administrator
  `/admin/devices` workspace, migration `0009_domain_foundation` for reading
  provenance/timestamps, shared manual/device validation, and regression
  coverage. Duplicate suppression remains deferred
until the hardware supplies a stable sample identifier. Device deletion,
primary-device designation, production bridge orchestration, and deferred sensor
hardware remain out of scope.

## 2026-08-21 — Lock Phase 02 monitoring and alert lifecycle behavior

**Decision:** Keep strict threshold ordering and open comparisons, with exact
warning and critical boundaries remaining Normal. Use server receipt time and a
90-second window for freshness. Derive tank status from the worst present,
enabled value, treat missing values as Unavailable, and use Offline when no
usable fresh value exists. Keep threshold changes prospective.

Use one active alert per tank and parameter. Allow Warning/Critical escalation
and downgrade, automatically resolve only when the same parameter returns to a
fresh normal value, and create a new incident when a later abnormal period
returns. Record manual and automatic resolution sources separately; automatic
resolutions create an administrator-only audit event. Keep notifications
in-app only and defer external delivery.

**Reason:** These rules make the existing threshold, freshness, and alert
behavior deterministic without introducing per-tank configuration,
notification infrastructure, or analytics redesign.

**Consequences:** Alert responses gain additive `resolution_source` metadata and
the database requires migration `0010_alert_resolution_source`. Historical
threshold revisions remain intact. Legacy resolved alerts with unknown source
remain nullable. Deferred sensor compatibility fields and external
notifications remain outside the current release.

## 2026-08-21 — Keep Phase 03 species care advisory and compatibility notes-only

**Decision:** Keep species care profiles as administrator-managed reference
data, allow staff to assign and remove species from tanks, and keep assignment
history in the existing audit trail. Derive suitability from temperature, pH,
and TDS using inclusive, one-sided-capable preferred ranges and the Phase 02
receipt-time freshness rule. Use Attention before Unavailable before Suitable
when aggregating configured checks. Exclude dissolved oxygen and ammonia from
the approved suitability workflow.

Keep compatibility as free-text `compatibility_notes`. Defer pairwise scoring,
stocking recommendations, compatibility-based assignment blocking, and a
dedicated assignment-history workspace.

Approve a reduced public species projection containing common/scientific name,
photo, care group, description, diet details, and care tips. Omit preferred
ranges, compatibility notes, assignment metadata, and suitability metadata from
that public projection.

**Reason:** The current product already supports useful species profiles,
assignment workflows, and advisory care guidance. The client needs clear,
explainable information without unsupported automated compatibility or deferred
sensor behavior. Public pages should expose approved care copy without leaking
internal management or suitability context.

**Consequences:** The Phase 03 documentation records the intended boundaries;
the implementation decision below records the subsequent contract hardening.
Assignment and species-profile audit events remain the current history surface.

## 2026-08-21 — Implement Phase 03 public species and suitability boundaries

**Decision:** Activate the reduced public species projection containing common
and scientific name, photo, care group, description, diet details, and care
tips. Redact public species IDs, preferred ranges, compatibility notes,
assignment metadata, and suitability metadata. Restrict species suitability to
temperature, pH, and TDS, using the Phase 02 receipt-time freshness rule. Keep
the legacy `ideal_do_min` database column and internal sensor compatibility
fields without exposing them in the current species-care or public contracts.

**Reason:** The public tank page needs customer-safe care copy, while the
species-care evaluator must not imply support for deferred dissolved oxygen or
ammonia workflows. A dedicated projection makes the boundary explicit at the
backend schema instead of relying on browser filtering.

**Consequences:** The existing public tank route and assignment workflow remain
unchanged, but their response projections are narrower. No migration is
required. Compatibility notes remain authenticated staff reference data,
pairwise compatibility remains deferred, and assignment history remains
available through audit events only.

## 2026-08-21 — Reconcile Phase 04 operations boundaries

**Decision:** Keep Phase 04 as five related operations specifications covering
Fleet Overview, Tank Workspace, Alert History, Analytics, and Public Tank
Pages. Treat the current implementation as authoritative, keep analytics
user-facing metrics limited to temperature, pH, turbidity, and TDS, and preserve
public tank pages as read-only privacy-safe projections. Record server receipt
time as the approved future boundary for analytics bucketing, uptime, and gap
detection while retaining observation time for historical context. Keep
pagination, real-time streaming, external notifications, predictive analytics,
and customer-facing fleet workflows deferred. Rename the public timestamp label
from “Updated” to “Observed” in a future web polish pass without adding public
receipt metadata.

**Reason:** The operations UI and APIs are already implemented, but the Phase 04
deep specs contained placeholders and did not consistently distinguish current
behavior from later hardening. Receipt-time freshness is already authoritative
for fleet and tank operations, while analytics still uses observation time. The
public contract must remain narrower than authenticated operations data.

**Consequences:** The Phase 04 documents now describe current routes, states,
permissions, filters, calculations, and privacy boundaries. No executable code,
API route, schema, migration, or UI behavior changes in this documentation pass.
Receipt-time analytics and the public “Observed” wording remain explicit future
work items.

## 2026-08-21 — Implement receipt-time Phase 04 operations hardening

**Decision:** Use server `received_at` for analytics filtering, ordering,
bucket placement, uptime intervals, and reporting-gap detection. Retain reading
`timestamp` for historical and hardware-clock context. Preserve the existing
analytics response shape, including nullable deferred dissolved-oxygen and
ammonia compatibility fields. Label the public observation timestamp “Observed”
without exposing public receipt metadata.

**Reason:** Fleet and tank operations already use receipt time for freshness and
latest-reading selection. Analytics must use the same operational boundary so
late observations cannot distort reporting health or trend windows. The public
page's timestamp is observation time, so “Observed” is more precise than
“Updated”.

**Consequences:** No route, schema, migration, role, or dependency changes are
required. Existing analytics controls, threshold overlays, alert event timing,
CSV export, and deferred metric compatibility remain intact. Regression tests
now cover late observations, receipt-time buckets, uptime, and gaps. Pagination,
WebSockets, external notifications, predictive analytics, and database-level
aggregation remain deferred.

## 2026-08-21 — Reconcile Phase 05 equipment-control documentation

**Decision:** Treat the current actuator implementation as the Phase 05
authority. Keep browser actuator controls administrator-only, keep bridge access
device-key-only with fixed device-to-tank mapping, and document UV, normal LED,
and feeder schedules as device-resident configuration. AquaLogic validates and
queues one schedule command, the bridge forwards it once, and the ESP32 owns
future local execution. Record the exact 120-second normal-command and
20-second pump-command default expiries, their 300/30-second maxima, and the
no-blind-retry command safety rule. Keep Pump A/B as online-required,
maintenance-only, empty-syringe/water-only checks.

**Reason:** The backend, bridge, and web controls already implement these
boundaries, but several Phase 05 deep specs were placeholders or left command
semantics unresolved. Device-resident schedule execution matches the existing
ESP32 routes without inventing a backend scheduler. Treating ambiguous physical
requests as non-retryable prevents duplicate physical actions.

**Consequences:** The Phase 05 documents now distinguish command acceptance from
future physical state and schedule execution. Manual retry means creating a new
command only after inspecting the equipment; there is no retry endpoint or
automatic hardware retry. Last-known actuator state remains non-authoritative
when the bridge is stale or offline. Audit retention, archive/export behavior,
and system attribution for future scheduler-generated commands remain deferred.
Production fail-safe hardware behavior, timezone/device-clock management, and
future scheduler workers require separate design and validation.

## 2026-08-22 — Persist uncertain actuator outcomes and serialize pump dispenses

**Decision:** Add terminal `outcome_unknown` reconciliation for commands that
were claimed but lack a trustworthy result after a 180-second post-claim
confirmation window. Keep queue expiry limited to `queued`, reject late bridge
reports with deterministic `409 Conflict`, and never retry or replay a physical
request. Block a second `dispense` only for the same registered device and pump
while the earlier command is executing or uncleared unknown. Record
administrator physical verification (actor, time, and bounded note) to clear the
software lock without rewriting the historical outcome; keep Stop available.

**Reason:** A lost bridge/backend report cannot prove that a physical actuator
did not run. The conservative terminal state prevents duplicate pump dosing
while still allowing a deliberate, attributable operator decision after local
inspection. PostgreSQL row locking and SQLite `BEGIN IMMEDIATE` serialize the
same-device pump check and claim recheck without weakening atomic claim-before-
execution.

**Consequences:** History/API/UI expose the unknown state and summary count, and
hardware validation must confirm the 180-second window is longer than the
bridge's maximum legitimate completion/report path. Automatic dosing, command
replay, generalized scheduling, and fleet job infrastructure remain deferred.

## 2026-08-22 — Clean owned tank media after committed deletion

**Decision:** Keep tank deletion relationally authoritative and database-first.
Capture the current hero URL, commit the audit event and cascade, then best-effort
remove only an AquaLogic-owned local path contained by `MEDIA_ROOT`. Missing,
external, and out-of-root paths are ignored; post-commit filesystem failures are
logged without attempting to reverse the committed deletion.

**Reason:** Deleting media before the database transaction can orphan the
relational reference when a commit fails. Deleting arbitrary or hosted paths
would exceed AquaLogic's ownership boundary. A committed database delete must
not be reported as failed solely because local cleanup needs operator follow-up.

**Consequences:** The permanent-delete warning and workflow must distinguish
relational cleanup from physical hardware decommissioning. Device-resident
schedules and physical state require manual action. The implemented retired-tank
lifecycle now gates permanent deletion, but this change does not introduce
remote teardown.

## 2026-08-22 — Treat hardware movement as reprovisioning

**Decision:** Move equipment by deactivating the old fixed device registration,
physically moving and verifying the hardware, provisioning a new destination
registration and one-time key, confirming destination-only readings and
actuator identity, and recreating only intended device-resident schedules.

**Reason:** Editing `tank_id`, migrating historical readings, reusing keys, or
assuming firmware state moved would blur historical ownership and could direct
controls at the wrong physical tank.

**Consequences:** The existing Devices API remains activation/deactivation,
rotation, and provisioning only. No reassignment, remote firmware reset,
schedule cloning, or device deletion is added; unresolved physical checks
remain operator responsibilities.

## 2026-08-22 — Make monitoring and Species Care wording explicit

**Decision:** Present offline or stale sensor values as last-known context and
derive reporting age from server receipt time. Call the operator alert action
**Mark handled** while retaining the `/alerts/{alert_id}/resolve` backend route
and `operator` resolution metadata. Explain operational status as global
threshold evaluation, label Species Care as water-only advisory guidance, and
state that exact threshold boundaries remain Normal.

**Reason:** The monitoring, alert, and Species Care engines already implement
these semantics, but concise UI labels could imply current readings, physical
recovery, fish compatibility, or inclusive threshold comparisons.

**Consequences:** The change is presentation-only: no freshness window,
threshold comparison, alert lifecycle, deduplication, or Species Care evaluator
behavior changes. Fish compatibility remains notes-only and undecided, and the
authenticated web derives tank-detail age from the existing reading
`received_at` field without an API migration.

## 2026-08-23 — Classify ambiguous bridge failures conservatively and reconcile unattended

**Decision:** Keep `failed` for confirmed pre-dispatch or explicit
non-ambiguous rejection only. A physical-call timeout, lost or malformed
terminal response, completion timeout, or state-poll failure is reported as
`outcome_unknown`; the bridge makes no blind retry and may issue only the
existing one-shot pump safety stop. Add the device-key uncertainty report
route, and run the existing idempotent actuator reconciler from the shared
periodic maintenance loop already used for unattended monitoring incidents.
Lock permanent tank deletion with the established tank lifecycle mutation
lock.

**Reason:** A claimed request can reach equipment even when AquaLogic loses the
response. Treating that branch as ordinary failure bypasses the same-pump
uncertainty interlock and can permit a duplicate dispense. The small shared
maintenance loop closes the unattended reconciliation gap without introducing
a job platform. Deletion must participate in the same SQLite/PostgreSQL
serialization boundary as retirement to avoid contradictory lifecycle results.

**Consequences:** The API now distinguishes confirmed failure from ambiguous
physical outcome, while the existing history, verification, late-report, and
same-pump contracts remain stable. No migration is required because the
existing `outcome_unknown`, verification, and audit fields already represent
the state. Hardware validation must exercise normal completion, timeout/late
report behavior, one-shot safety stop, and duplicate-dispense prevention with
empty syringes or water only. External notifications, automatic dosing,
command replay, generalized scheduling, and enterprise job infrastructure
remain deferred.

## Adding a decision

Use this format:

```md
## YYYY-MM-DD — Short decision title

**Decision:** What will be done.

**Reason:** Why this choice was made.

**Consequences:** What this makes easier, harder, or deferred.
```

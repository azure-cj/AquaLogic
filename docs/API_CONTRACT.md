# AquaLogic API Contract

Status: Current route inventory
Last reviewed: 2026-09-25

The running FastAPI application at `backend/app/main.py` is the executable
contract. This document is a navigation aid; response models and tests remain
the final authority for exact fields and validation.

## Authentication

Authenticated routes use the 15-minute bearer token returned by `POST /auth/login`
or `POST /auth/refresh`. The browser keeps this token in memory; the seven-day
opaque refresh token is an HttpOnly, SameSite=Strict cookie. All access tokens
carry session and token-version claims, so legacy tokens intentionally fail.

The Flutter client calls the FastAPI root directly at the configured Railway
base URL; it does not use the Vercel web app's `/api` proxy. Native auth keeps
the access token in memory, stores only the opaque refresh-cookie value in
platform secure storage, and sends `Cookie: aqualogic_refresh=...` only to
`POST /auth/refresh`. It does not depend on browser SameSite or CORS behavior.
Login and password-change responses rotate the refresh cookie when issuing a
new session; a refresh response without a replacement cookie is the backend's
five-second replay grace path, so clients retain the existing value.

## Mobile Home reads

The Flutter Home repository uses the shared authenticated client for
`GET /fleet`, `GET /alerts` (unresolved by default), and
`GET /monitoring-incidents?state=active&page=1&page_size=100`. All three require
staff access; backend `admin` is accepted by `require_staff`. Fleet operational
status and `reporting_age_seconds` are authoritative. The incident response is
paginated: Home uses `total` for the count and only the newest page for priority
incident details. Alert handling remains a separate operator mutation through
`PUT /alerts/{alert_id}/resolve`; monitoring incidents have no manual resolve
route. These reads do not provide recent activity.

| Method | Route | Access | Purpose |
| --- | --- | --- | --- |
| POST | `/auth/login` | Public | Authenticate an active user |
| POST | `/auth/logout` | Authenticated | Client-side JWT logout acknowledgement |
| POST | `/auth/refresh` | Refresh cookie | Rotate the refresh token and return a new access token |
| POST | `/auth/logout-all` | Authenticated | Verify current password and revoke every session |
| GET | `/auth/me` | Authenticated | Read current user |
| POST | `/auth/change-password` | Authenticated | Complete or change password |
| POST | `/auth/setup-password` | Setup link | Atomically activate or reset an account from a one-time token |
| GET/DELETE | `/auth/sessions` and `/auth/sessions/{session_id}` | Authenticated | List/revoke the caller's sessions |

User creation and reset responses return one-time `setup_url` values rather
than plaintext passwords. Setup links are fragment tokens and expire after 30
minutes. Password changes and resets revoke existing sessions.

## Mobile Tanks reads

The Flutter Tanks directory uses one `GET /fleet` request and applies search
and status filters locally. Live detail combines `GET /tanks/{tank_id}`,
`GET /tanks/{tank_id}/operations`,
`GET /tanks/{tank_id}/monitoring-incidents?state=active&page=1&page_size=100`,
and `GET /tanks/{tank_id}/species-suitability`. These require staff access;
`admin` is accepted by the backend's staff guard. Tank metadata is required;
operations, incident, or suitability failures are presented independently as
unavailable data. Operations supplies the current reading, parameter status,
and active water-quality alerts. Active monitoring incidents are operational
state, separate from water-quality alerts. No equipment-state or recent tank
activity API is used by the mobile M3 detail view.

## Core staff resources

| Method | Route | Purpose |
| --- | --- | --- |
| GET/POST | `/tanks` | Staff list (active by default; `lifecycle=active|retired|all`); admin creates |
| GET/PUT/DELETE | `/tanks/{tank_id}` | Staff reads; admin updates active tanks or permanently deletes retired tanks |
| POST | `/tanks/{tank_id}/retire` | Admin-only, idempotent one-way transition to retired; deactivates registered devices and preserves history |
| POST | `/tanks/{tank_id}/hero-image` | Admin-only; upload a JPG, PNG, or WebP hero image up to 5 MB |
| GET | `/tanks/{tank_id}/species-suitability` | Derive staff-only species-care suitability from the latest reading |
| POST/DELETE | `/tanks/{tank_id}/fish` and `/tanks/{tank_id}/fish/{fish_id}` | Manage tank/species assignments |
| GET/POST | `/fish` | Staff lists; admin creates |
| GET/PUT/DELETE | `/fish/{fish_id}` | Staff reads; admin updates or deletes |
| POST | `/fish/{fish_id}/photo-image` | Admin-only; upload a JPG, PNG, or WebP species photo up to 5 MB |
| GET | `/tanks/{tank_id}/sensors` | Read latest sensor data |
| GET | `/tanks/{tank_id}/sensors/history` | Read bounded sensor history |
| POST | `/tanks/{tank_id}/sensors` | Admin-only manual sensor submission |
| GET | `/alerts` | List active or all alerts |
| GET | `/alerts/history` | Filter alert history |
| GET | `/tanks/{tank_id}/alerts` | List alerts for a tank |
| PUT | `/alerts/{alert_id}/resolve` | Legacy route used by the UI's **Mark handled** action; closes the alert record without confirming water recovery |
| GET | `/monitoring-incidents` | Staff/admin paginated monitoring-outage history; defaults to active and supports tank, state, and start-time filters |
| GET | `/tanks/{tank_id}/monitoring-incidents` | Staff/admin paginated monitoring-outage history for one tank |
| POST | `/devices` | Admin-only one-time device provisioning; returns a key once and fixes the device to one tank |
| GET | `/devices` | Admin-only sanitized device inventory with derived online/offline/disabled status |
| GET | `/devices/{device_id}` | Admin-only sanitized device detail |
| PATCH | `/devices/{device_id}` | Admin-only activation or deactivation through `{ "is_active": boolean }` |
| POST | `/devices/{device_id}/rotate-key` | Admin-only one-time replacement key; invalidates the previous key |
| POST | `/device-ingestion/readings` | Device key only; accepts temperature, pH, turbidity, TDS and maps them to the provisioned tank |
| POST | `/tanks/{tank_id}/actuators/commands` | Admin-only; queue one validated UV, LED, feeder, or guarded pump-maintenance command for the tank's registered bridge device |
| POST | `/tanks/{tank_id}/actuators/commands/{command_id}/clear-uncertainty` | Admin-only; record physical verification for an `outcome_unknown` command without rewriting its historical status |
| GET | `/tanks/{tank_id}/actuators/status` | Admin-only; read bridge freshness and last-known UV, LED, feeder, and pump state |
| GET | `/tanks/{tank_id}/actuators/history` | Admin-only; read paginated command audit history with actor, timestamps, status, result, and error |

Retirement is administrator-only and one-way (`active -> retired`). It records
`retired_at`, the retiring administrator, and an optional bounded note, forces
the tank private, clears its monitoring expectation, deactivates all registered
devices in the same transaction, and records one `tank.retire` audit event.
Repeated retirement returns the existing retired representation without
repeating side effects. Retirement is rejected while actuator work is executing
or an `outcome_unknown` command still lacks physical verification. It does not
erase device-resident schedules or physical state; follow the hardware
decommissioning checklist first.

Authenticated tank lists default to active and support `lifecycle=retired` and
`lifecycle=all`. `/fleet` and default analytics exclude retired tanks. Historical
analytics can include them with `include_retired=true`, and retired detail,
readings, alerts, configuration, media, and authorized actuator history remain
readable. Retired tanks are never returned by the public route. Operational
writes, device ingestion/reactivation, actuator command creation, assignments,
manual readings, and configuration/media edits are rejected with a stable
retired/read-only conflict. Permanent tank deletion is administrator-only and
only available after retirement; it then cascades the tank's
sensor readings, alerts, species assignments, registered devices, actuator
commands, and actuator state history. An AquaLogic-owned local uploaded hero
image is removed only after the database commit succeeds. Missing files are
idempotent; external HTTPS image URLs and paths outside the configured media
root are never deleted. A post-commit filesystem failure is logged without
rolling back the committed deletion. The operation does not clear ESP32
schedules, firmware configuration, or physical equipment state. Follow the
[tank deletion and hardware decommissioning workflow](WORKFLOWS.md#tank-deletion-and-hardware-decommissioning)
before using the retirement or permanent-deletion endpoint. Persistent
monitoring incidents are separate from water-quality alerts: the detector opens
one active row per eligible tank after the configured 900-second default grace,
accepted readings resolve it as `reporting_recovered`, last-device deactivation
resolves it as `monitoring_disabled`, and retirement resolves it as
`tank_retired`. The authenticated incident routes are paginated and expose
interval/receipt context without device credentials. No manual resolution or
external notification route exists.

The device-key bridge routes are not browser routes:

| Method | Route | Access | Purpose |
| --- | --- | --- | --- |
| GET | `/device-ingestion/actuators/pending` | Registered device key | Fetch unexpired commands for that exact device |
| POST | `/device-ingestion/actuators/{command_id}/executing` | Registered device key | Claim one command before any ESP32 call |
| POST | `/device-ingestion/actuators/{command_id}/succeeded` | Registered device key | Idempotently report a completed local call |
| POST | `/device-ingestion/actuators/{command_id}/failed` | Registered device key | Report a confirmed validation, pre-dispatch, or explicit non-ambiguous rejection |
| POST | `/device-ingestion/actuators/{command_id}/outcome-unknown` | Registered device key | Report that a physical request may have begun but no trustworthy terminal result is available |
| POST | `/device-ingestion/actuator-state` | Registered device key | Store refreshed local actuator state |

## Operations and administration

| Method | Route | Access | Purpose |
| --- | --- | --- | --- |
| GET | `/fleet` | Staff | Fleet overview and reporting state |
| GET | `/analytics/fleet` | Staff | Fleet/tank trends, effective historical threshold context, alert events, comparisons, and uptime; `include_retired=true` opts retired tanks into historical scope |
| GET | `/thresholds` | Staff | Read global threshold defaults |
| PUT | `/thresholds/{parameter}` | Admin | Update one global parameter default |
| GET | `/tanks/{tank_id}/thresholds` | Staff | Read each parameter's effective threshold and whether it is inherited or overridden |
| PUT | `/tanks/{tank_id}/thresholds/{parameter}` | Admin | Save a complete override for an active tank and parameter |
| DELETE | `/tanks/{tank_id}/thresholds/{parameter}` | Admin | Remove a tank override so it inherits the global default again |
| GET/POST | `/customers` | Staff reads; admin creates |
| PUT/DELETE | `/customers/{customer_id}` | Admin | Update or delete customers |
| GET | `/users` | Admin | List staff users with derived lifecycle status, password-change timestamp, active-session count, and latest activity |
| GET | `/users/{user_id}` | Admin | Read one user's lifecycle summary |
| GET | `/users/{user_id}/sessions` | Admin | Read sanitized active sessions for one user; exposes no IP hashes, refresh tokens, or token hashes |
| POST | `/users/{user_id}/revoke-sessions` | Admin | Revoke every session for another user, increment token version, and record an audit event |
| PUT | `/users/{user_id}` | Admin | Update role or active state |
| POST | `/users` | Admin | Create a user and return a one-time setup URL |
| POST | `/users/{user_id}/reset-password` | Admin | Disable the password/sessions and issue a setup URL |
| GET | `/security/audit-events` | Admin | Read up to 100 newest security audit events before an optional ID; optionally filter by user, event type, outcome, and time range |

The administrator `/users` and `/users/{user_id}` responses add these derived
fields without a database migration: `account_status` (`active`,
`setup_required`, or `inactive`), `password_changed_at`,
`active_session_count`, and `last_activity_at`. The audit `user_id` filter
matches events performed by that user or events targeting that user account.
Administrator session revocation cannot target the administrator's own account;
the personal `/auth/logout-all` flow remains the self-service operation.

## Public route

| Method | Route | Access | Purpose |
| --- | --- | --- | --- |
| GET | `/public/tanks/{public_id}` | Public | Read a public QR tank view |

The public route only returns tanks marked public and uses the public identifier.
The web route consuming it is `/tank/:publicId`.

It exposes only `display_location`, not the internal location; excludes tank
code and feeding schedule; rounds readings; and rounds observation timestamps to
the minute. Public image URLs require HTTPS and a configured host allowlist.

Public `fish_species` entries contain only `common_name`, `scientific_name`,
`photo_url`, `category`, `description`, `diet`, and `care_tips`. They omit
internal IDs, preferred ranges, `ideal_do_min`, compatibility notes, assignment
metadata, and suitability metadata. Public readings contain only `timestamp`,
`temperature`, `ph`, `turbidity`, and `tds`; public parameter statuses and
overall status use those same four active parameters. Dissolved oxygen and
ammonia remain database compatibility fields and cannot affect the public
projection or status.

Admin hero and species-photo uploads are stored under the configured
`MEDIA_ROOT` and returned as same-application `/api/media/tanks/...` or
`/api/media/fish/...` URLs. Local disk storage is suitable for the local-first
demo; production deployment needs a persistent volume or object-storage
adapter before uploaded images are considered durable. The browser may still
use a hosted species-photo URL through the existing `photo_url` field.

## Operational endpoints and notes

- Bridge ingestion uses `X-Device-Key`, never a browser JWT, staff password, or
  client-supplied tank ID. Keys are stored as hashes and successful/denied
  ingestion is audit logged. The v1 payload accepts only `temperature`, `ph`,
  `turbidity`, `tds`, and optional `observed_at`; dissolved oxygen and ammonia
  persist as unavailable nulls and cannot create normal statuses or alerts.
  Accepted installed ranges are temperature `-10..60`, pH `0..14`, turbidity
  `0..3000`, and TDS `0..5000`. Reading responses include nullable `device_id`
  and server-generated `received_at`; manual readings have no source device.
  Freshness uses `received_at`, while `timestamp` remains the observation time.

- Device list/detail responses expose only the device ID, fixed tank mapping,
  activation state, created time, last-seen time, and derived status. They never
  expose a raw key or key hash. Deactivation immediately rejects device-key
  ingestion and actuator routes. Multiple active devices per tank remain
  supported, with explicit selection required where an operation needs one.
  Physical movement is handled as deactivation plus new provisioning; key
  rotation replaces credentials for the same fixed mapping and is not a
  reassignment. Follow the [canonical move/reprovisioning workflow](WORKFLOWS.md#moving-equipment-to-another-tank)
  for physical confirmation and schedule recreation.

- Actuator command APIs are admin-only. Staff actuator command, state, and
  history requests receive `403`; the web UI does not fetch those endpoints for
  staff accounts. Commands use a server-generated ID, a server-selected fixed
  device/tank mapping, a validated payload, and a short expiry. Lifecycle
  status is `queued`, `executing`, `succeeded`, `failed`, `expired`, or
  `outcome_unknown`. `outcome_unknown` means the command was claimed and may
  have reached equipment, but no trustworthy terminal result arrived within
  the confirmation window; it is not a retryable or expired state.
  `failed` is reserved for a confirmed pre-dispatch failure or explicit
  non-ambiguous hardware rejection; it is not a generic timeout bucket.

- Normal UV, LED, and feeder commands default to a 120-second queue expiry and
  accept at most 300 seconds. Pump maintenance commands default to 20 seconds
  and may not exceed 30 seconds. A queued command must be claimed by the
  registered bridge before any physical request; expired commands are never
  delivered. There is no automatic hardware retry or retry endpoint. An
  operator must inspect the equipment before creating a new command. The server
  confirmation window is 180 seconds from claim, independent of queue expiry;
  it covers the bridge's permitted 120-second pump completion wait, bounded
  request/report time, and scheduling/network margin.

- `GET /tanks/{tank_id}/actuators/history` accepts `page` (default `1`),
  `page_size` (default `10`, maximum `50`), and optional exact-match
  `actuator` (`uv`, `led`, `feeder`, `pump_a`, or `pump_b`) and `status` (`queued`, `executing`,
  `succeeded`, `failed`, `expired`, or `outcome_unknown`) filters. It returns
  `{items, page, page_size, total, total_pages, has_previous, has_next,
  summary}` ordered newest first. `summary` contains fixed-device totals for
  `total`, `queued`, `executing`, `succeeded`, `failed`, `expired`, and
  `outcome_unknown`, so the
  dashboard can preserve useful lifecycle context while filters are active. The
  web dashboard uses the pagination metadata for previous/next controls instead
  of loading an unbounded audit list.

- The device-key actuator boundary is `GET
  /device-ingestion/actuators/pending`, `POST
  /device-ingestion/actuators/{command_id}/executing`, `POST
  /device-ingestion/actuators/{command_id}/succeeded`, `POST
  /device-ingestion/actuators/{command_id}/failed`, `POST
  /device-ingestion/actuators/{command_id}/outcome-unknown`, and `POST
  /device-ingestion/actuator-state`. It verifies that every command belongs to
  the authenticated device's fixed tank. Duplicate claims/final reports are
  idempotent and cannot requeue a finalized command. A late success/failure
  report after `outcome_unknown` returns deterministic `409 Conflict`, is
  recorded as late evidence rejection once per distinct report, and never
  overwrites the unknown status.

- The bridge uses `failed` only for a trustworthy pre-dispatch or explicit
  rejection. A timeout, lost response, malformed terminal response, completion
  timeout, or state-polling failure after a physical request may have begun is
  reported as `outcome_unknown`. The bridge makes no blind retry; a pump
  completion timeout may still receive one intentional safety stop, which does
  not prove the original dispense outcome.

- A same-device, same-pump `dispense` is rejected with `409` while another
  dispense for that pump is `executing` or uncleared `outcome_unknown`. Pump A
  does not block Pump B or a different registered device. `stop` and `retract`
  remain queueable. An administrator can call the uncertainty-clearance route
  with an optional bounded note; the response remains `outcome_unknown` and
  exposes the verifier, verification time, and note.

- v1 accepts UV (`on`, `off`, `timer`, `schedule`), normal LED (`on`,
  `off`, `timer`, `schedule`), and feeder (`feed_now`, `config`, `schedule`)
  actions. Light timers are bounded to 1–86,400,000 ms; schedule values use
  `HH:MM`; feeder configuration is angle 0–180 and duration 500–60,000 ms with
  exactly three schedule slots. Pump `pump_a` and `pump_b` manual-test actions
  are limited to `dispense`, `stop`, and `retract`; dispense has an empty
  payload because the received firmware owns the configured `volume_ml` and
  exposes no volume-setting endpoint. The bridge waits for the configured
  volume move to finish and applies a bounded local safety timeout. Pump
  commands default to a 20-second queue expiry and may not exceed 30 seconds
  before the bridge claims them. Pump queue requests are rejected with `409`
  while the fixed bridge is offline, so they are never silently left in the
  queue. Pump schedules, pH auto-dose, and sensor-driven dosing remain out of
  scope.

- UV, LED, and feeder schedules are device-resident configuration. AquaLogic
  validates and queues one schedule command, the bridge forwards it once, and
  the ESP32 stores and executes it locally. A successful schedule command means
  the device accepted the configuration request; it does not confirm every
  future scheduled event. The current `HH:MM` contract has no timezone,
  daylight-saving, or device-clock synchronization fields.

- The received firmware's private pump routes are `/syringeA/status`,
  `/syringeA/dispense`, `/syringeA/stop`, `/syringeA/retract`, and the matching
  `/syringeB/*` routes. Only the bridge calls them. Dispense has no query
  parameters: the status `volume_ml` is informational, while the firmware's
  internal step count determines the physical dose. The browser and backend
  never connect to the ESP32.

- The bridge is the only component that calls local ESP32 routes. The browser
  and backend never connect to the ESP32. Tunnel infrastructure is temporary
  dashboard/API test infrastructure only; the ESP32 stays on the tester's
  private local Wi-Fi and is never publicly exposed.

- Alert responses include nullable `resolution_source`: `operator` for a
  manual **Mark handled** action, `system` for automatic resolution, and `null` for
  unresolved or legacy records with unknown history. Automatic resolution is
  triggered by a fresh normal reading for the same parameter or by the first
  usable reading after that parameter's threshold is disabled. It records an
  administrator-only `alert.auto_resolve` audit event; there is no separate
  notification-delivery API. Manual handling removes the record from the
  active queue but does not confirm that water conditions recovered; a later
  abnormal reading may create a new alert incident.

- Thresholds resolve per tank: a complete tank override replaces the global
  default for that parameter; otherwise the tank inherits the global default.
  Tank overrides include the full bound set and enabled state, and their unit is
  fixed from the global parameter configuration. Reset removes the override.
  Global and tank writes are administrator-only, require strict ordering of
  supplied bounds, and are prospective. Exact warning and critical boundaries
  remain Normal. Disabled effective thresholds expose the parameter as
  unavailable and create no new alerts. Saves and resets do not recalculate
  existing alerts or reclassify the latest reading's displayed status;
  operational and public status projections use the threshold revisions active
  at that reading's server `received_at`. A later usable reading applies the
  changed configuration.
- `GET /tanks/{tank_id}/thresholds` is an authenticated staff contract; numeric
  threshold configuration is not included in public tank responses. Public
  operational status and parameter statuses still use that tank's effective
  thresholds.

- `GET /health` is the deployment health check.
- CORS is configured from `CORS_ORIGINS`; production rejects wildcard CORS.
- Demo ingestion requires both `DEMO_SENSOR_ENABLED` and
  `DEMO_SENSOR_INSTANCE` to be enabled.
- Persistent monitoring incidents require `MONITORING_INCIDENTS_ENABLED=true`
  in production, use `MONITORING_OUTAGE_GRACE_SECONDS=900` by default, and run
  an idempotent detector every `MONITORING_INCIDENT_CHECK_INTERVAL_SECONDS=60`
  seconds. The grace must remain strictly greater than the 90-second Offline
  freshness window.
- Pagination is not yet available on the main list endpoints and is a known
  scaling limitation.
- Authenticated `GET /fish` and `GET /fish/{id}` responses include species care
  ranges (`ideal_temp_*`, `ideal_ph_*`, and `ideal_tds_*`), `category`,
  categorical `diet_type`, the derived `tank_count`, and safe `assigned_tanks`
  summaries containing only tank IDs and names. The public tank response uses a
  dedicated reduced species projection containing only common and scientific
  names, photo, care group, description, diet details, and care tips; it omits
  preferred ranges, compatibility notes, tank counts, assigned tanks, and
  suitability metadata. Deleting a species with
  active tank assignments returns `409 Conflict`; assignments must be removed
  first.
- `GET /tanks/{tank_id}/species-suitability` returns derived `suitable`,
  `attention`, or `unavailable` results for assigned species. It evaluates
  temperature, pH, and TDS against fish preferred ranges and selects the latest
  reading by server receipt time. It evaluates only temperature, pH, and TDS;
  legacy dissolved-oxygen storage is excluded. Suitability does not create
  alerts or use operational thresholds.
  The response includes per-parameter reasons, range values, a reading freshness
  reference, and `no_species_assigned` for empty tanks. Preferred temperature,
  pH, and TDS minimums may be omitted or equal to their maximums, but cannot
  exceed them. The result is advisory water-only guidance; it does not assess
  fish-to-fish compatibility, stocking density, temperament, or breeding behavior.
- `GET /tanks/{tank_id}/operations` returns one internally consistent, UTC
  evaluated operational snapshot: latest reading (or `null`), six
  threshold-backed parameter statuses, and unresolved persisted alerts newest
  first. A missing reading is `offline` with `unavailable` parameters; a stale
  reading is `offline` with `offline` parameters. When a reading exists, its
  `received_at` is the server receipt time available to authenticated clients;
  the web derives reporting age from it. `timestamp` remains the observation
  time and is not freshness evidence.
- `GET /tanks/{tank_id}` adds the optional minimal `customer` summary while
  retaining `customer_id` and assigned `fish_species`. `GET /fleet` adds the
  lightweight derived `species_care_status` and `assigned_species_count`, plus
  `reporting_age_seconds` calculated from the latest reading's server
  `received_at`; `last_reading_at` remains the observation timestamp. It does
  not expose per-species checks.
- `GET /analytics/fleet` accepts `range=24h|7d|30d|custom`,
  `bucket=auto|15m|1h|6h|1d`, and up to three repeated `tank_id` values.
  Custom requests require ISO `start` and `end` values, are limited to 30 days,
  and all requests are capped at 1,000 buckets. The response contains complete
  nullable timelines, fleet and selected-tank series, previous-period
  statistics, alert events, effective threshold segments, and classified
  reporting uptime. A single selected tank receives that tank's effective
  historical segments. Fleet or multi-tank scopes return shared segments only
  when effective histories match; otherwise `thresholds_vary_by_tank=true`,
  `threshold_scope="varies"`, and an empty `threshold_segments` list prevent a
  misleading shared threshold line.
- Analytics aggregation places readings, reporting intervals, and gaps by server
  `received_at`. Observation `timestamp` remains available for historical and
  hardware-clock context, and late observations are ordered operationally by
  receipt time.
- Fleet, tank, and alert list responses do not yet paginate. WebSocket streaming
  is not implemented; the current web dashboard uses bounded polling.
- A future WebSocket path may be added; the current
  `backend/app/websockets/sensor_stream.py` is only a placeholder.

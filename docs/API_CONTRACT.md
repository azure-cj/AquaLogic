# AquaLogic API Contract

Status: Current route inventory
Last reviewed: 2026-08-21

The running FastAPI application at `backend/app/main.py` is the executable
contract. This document is a navigation aid; response models and tests remain
the final authority for exact fields and validation.

## Authentication

Authenticated routes use the 15-minute bearer token returned by `POST /auth/login`
or `POST /auth/refresh`. The browser keeps this token in memory; the seven-day
opaque refresh token is an HttpOnly, SameSite=Strict cookie. All access tokens
carry session and token-version claims, so legacy tokens intentionally fail.

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

## Core staff resources

| Method | Route | Purpose |
| --- | --- | --- |
| GET/POST | `/tanks` | Staff list; admin creates |
| GET/PUT/DELETE | `/tanks/{tank_id}` | Staff reads; admin updates or deletes |
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
| PUT | `/alerts/{alert_id}/resolve` | Resolve an alert |
| POST | `/devices` | Admin-only one-time device provisioning; returns a key once and fixes the device to one tank |
| GET | `/devices` | Admin-only sanitized device inventory with derived online/offline/disabled status |
| GET | `/devices/{device_id}` | Admin-only sanitized device detail |
| PATCH | `/devices/{device_id}` | Admin-only activation or deactivation through `{ "is_active": boolean }` |
| POST | `/devices/{device_id}/rotate-key` | Admin-only one-time replacement key; invalidates the previous key |
| POST | `/device-ingestion/readings` | Device key only; accepts temperature, pH, turbidity, TDS and maps them to the provisioned tank |
| POST | `/tanks/{tank_id}/actuators/commands` | Admin-only; queue one validated UV, LED, or feeder command for the tank's registered bridge device |
| GET | `/tanks/{tank_id}/actuators/status` | Admin-only; read bridge freshness and last-known UV, LED, and feeder state |
| GET | `/tanks/{tank_id}/actuators/history` | Admin-only; read paginated command audit history with actor, timestamps, status, result, and error |

The device-key bridge routes are not browser routes:

| Method | Route | Access | Purpose |
| --- | --- | --- | --- |
| GET | `/device-ingestion/actuators/pending` | Registered device key | Fetch unexpired commands for that exact device |
| POST | `/device-ingestion/actuators/{command_id}/executing` | Registered device key | Claim one command before any ESP32 call |
| POST | `/device-ingestion/actuators/{command_id}/succeeded` | Registered device key | Idempotently report a completed local call |
| POST | `/device-ingestion/actuators/{command_id}/failed` | Registered device key | Report a local validation, timeout, or response failure |
| POST | `/device-ingestion/actuator-state` | Registered device key | Store refreshed local actuator state |

## Operations and administration

| Method | Route | Access | Purpose |
| --- | --- | --- | --- |
| GET | `/fleet` | Staff | Fleet overview and reporting state |
| GET | `/analytics/fleet` | Staff | Fleet/tank trends, historical threshold context, alert events, comparisons, and uptime |
| GET | `/thresholds` | Staff | Read threshold configuration |
| PUT | `/thresholds/{parameter}` | Admin | Update one parameter threshold |
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

- Actuator command APIs are admin-only. Staff actuator command, state, and
  history requests receive `403`; the web UI does not fetch those endpoints for
  staff accounts. Commands use a server-generated ID, a server-selected fixed
  device/tank mapping, a validated payload, and a short expiry. Lifecycle
  status is `queued`, `executing`, `succeeded`, `failed`, or `expired`.

- `GET /tanks/{tank_id}/actuators/history` accepts `page` (default `1`),
  `page_size` (default `10`, maximum `50`), and optional exact-match
  `actuator` (`uv`, `led`, `feeder`, `pump_a`, or `pump_b`) and `status` (`queued`, `executing`,
  `succeeded`, `failed`, or `expired`) filters. It returns
  `{items, page, page_size, total, total_pages, has_previous, has_next,
  summary}` ordered newest first. `summary` contains fixed-device totals for
  `total`, `queued`, `executing`, `succeeded`, `failed`, and `expired`, so the
  dashboard can preserve useful lifecycle context while filters are active. The
  web dashboard uses the pagination metadata for previous/next controls instead
  of loading an unbounded audit list.

- The device-key actuator boundary is `GET
  /device-ingestion/actuators/pending`, `POST
  /device-ingestion/actuators/{command_id}/executing`, `POST
  /device-ingestion/actuators/{command_id}/succeeded`, `POST
  /device-ingestion/actuators/{command_id}/failed`, and `POST
  /device-ingestion/actuator-state`. It verifies that every command belongs to
  the authenticated device's fixed tank. Duplicate claims/final reports are
  idempotent and cannot requeue a finalized command.

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
  manual Resolve action, `system` for automatic resolution, and `null` for
  unresolved or legacy records with unknown history. Automatic resolution is
  triggered by a fresh normal reading for the same parameter or by the first
  usable reading after that parameter's threshold is disabled. It records an
  administrator-only `alert.auto_resolve` audit event; there is no separate
  notification-delivery API.

- Threshold updates are administrator-only, require strict ordering of supplied
  bounds, and apply prospectively to the next valid reading. Exact warning and
  critical boundaries remain Normal. Disabled thresholds expose the parameter
  as unavailable and create no new alerts.

- `GET /health` is the deployment health check.
- CORS is configured from `CORS_ORIGINS`; production rejects wildcard CORS.
- Demo ingestion requires both `DEMO_SENSOR_ENABLED` and
  `DEMO_SENSOR_INSTANCE` to be enabled.
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
  exceed them.
- `GET /tanks/{tank_id}/operations` returns one internally consistent, UTC
  evaluated operational snapshot: latest reading (or `null`), six
  threshold-backed parameter statuses, and unresolved persisted alerts newest
  first. A missing reading is `offline` with `unavailable` parameters; a stale
  reading is `offline` with `offline` parameters.
- `GET /tanks/{tank_id}` adds the optional minimal `customer` summary while
  retaining `customer_id` and assigned `fish_species`. `GET /fleet` adds the
  lightweight derived `species_care_status` and `assigned_species_count`; it
  does not expose per-species checks.
- `GET /analytics/fleet` accepts `range=24h|7d|30d|custom`,
  `bucket=auto|15m|1h|6h|1d`, and up to three repeated `tank_id` values.
  Custom requests require ISO `start` and `end` values, are limited to 30 days,
  and all requests are capped at 1,000 buckets. The response contains complete
  nullable timelines, fleet and selected-tank series, previous-period
  statistics, alert events, effective threshold segments, and classified
  reporting uptime.
- A future WebSocket path may be added; the current
  `backend/app/websockets/sensor_stream.py` is only a placeholder.

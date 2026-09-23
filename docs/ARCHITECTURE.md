# AquaLogic Architecture

Status: Current implementation architecture
Last reviewed: 2026-09-23

## System overview

```mermaid
flowchart LR
    Web["React web: public tank + staff dashboard"] --> API["FastAPI backend"]
    API --> DB["SQLAlchemy + Alembic\nSQLite development / PostgreSQL target"]
    API --> Rules["Threshold decision engine"]
    Rules --> Alerts["Persisted alerts"]
    Demo["Optional demo sensor service"] --> API
    Mobile["Flutter staff prototype\nlocal demo data"] -. future API client .-> API
    Admin["Admin dashboard"] --> API
    ESP["ESP32 sensors + actuators on tester LAN"] --> Bridge["Temporary laptop bridge"]
    Bridge -->|"HTTPS tunnel / device key"| API
```

## Repository boundaries

### Backend

`backend/app/main.py` creates the FastAPI application, configures CORS, performs
development startup initialization, starts the optional demo sensor service,
and includes the route modules. The main implementation areas are:

- `app/models/`: SQLAlchemy persistence models, including registered devices,
  actuator commands, current actuator state, and state history.
- `app/schemas/`: Pydantic request and response models.
- `app/routes/`: auth, tanks, fish, sensors, devices, alerts, public, management,
  and dashboard endpoints. `devices.py` owns fixed-tank sensor ingestion and
  the device-key actuator boundary.
- `app/services/decision_engine.py`: effective threshold checks, status
  calculation, and alert creation.
- `app/services/thresholds.py`: global fallback and tank override resolution,
  plus tank-effective historical threshold segments.
- `app/services/species_suitability.py`: pure, staff-only derived species-care
  evaluation using the latest sensor reading and species preference fields.
- `app/services/tank_lifecycle.py`: centralized active-tank write guards,
  SQLite/PostgreSQL mutation locking, retirement actuator checks, and the
  explicit monitoring-expectation boundary.
- `app/services/demo_sensor.py`: opt-in local reading generation.
- `alembic/versions/`: database schema history.
- `tests/`: API and behavior tests using an isolated test database.

### Web

`web/src/app/` owns application composition, providers, routing, and lazy route
loaders. `web/src/features/` contains feature-level pages and styles. The
`shared/` directory contains the API client, shared models, reusable components,
hooks, and formatting utilities. `layouts/admin/` owns the persistent staff
navigation shell.

The web application has two trust boundaries:

- `/tank/:publicId` is public and read-only.
- `/admin/*` requires authenticated staff access, with admin-only operations
  enforced by the backend as well as reflected in navigation.

Authentication uses a short-lived HS256 access JWT held only in browser memory
and a rotating opaque refresh token held in a Strict, HttpOnly cookie. Every
authenticated request checks the JWT claims, user token version, and active
database session. Hash-only refresh/setup tokens, database throttles, and
append-only audit events support revocation and incident review.

### Mobile

`mobile_app/` is a Flutter prototype. Its current readings, alerts, fish data,
and control interactions are built from local demo data. It should not be
described as a backend client until an API client, authentication, and loading /
offline behavior are implemented.

### Firmware

`Aqualogic.ino` and the sibling library directories contain the embedded
starting point. Firmware integration should eventually send small, explicit
sensor payloads and receive validated commands. It is intentionally separated
from current web and backend work.

## Runtime data flow

1. Staff submits a manual reading for a tank, or a registered bridge device
   authenticates with a device key. Device keys resolve to one server-side tank;
   bridge requests cannot choose a tank.
2. The backend persists the reading.
3. The decision engine resolves each tank's complete per-parameter override,
   falling back to the global default, then evaluates enabled configurations.
4. Warning or critical alerts are created when values violate configured bounds,
   while unresolved alert duplication is controlled by the service logic.
5. A successfully accepted reading resolves the tank's active monitoring
   incident as reporting recovery in the same transaction; heartbeat, invalid,
   or rolled-back requests do not.
6. A lifespan-owned 60-second detector records one tank-level monitoring outage
   after the configured grace period, using the database uniqueness boundary so
   multiple API workers remain idempotent.
7. Authenticated web clients read fleet, incident history, alerts, and analytics
   data.
8. Public web clients read a restricted tank view by public ID.

Tank deletion is a database-first administrator operation serialized through
the same tank lifecycle lock as retirement. The route captures the current hero
URL, commits the audit event and relational cascade, and only
then attempts to remove an AquaLogic-owned local tank image. The safe media
helper confines deletion to the configured media root and the `/api/media/tanks/`
namespace, ignores missing or external files, and logs post-commit filesystem
failures without reversing the committed database change. Deletion does not
send hardware commands or imply that ESP32 schedules or physical state were
cleared; the operator procedure is in
[`docs/WORKFLOWS.md`](WORKFLOWS.md#tank-deletion-and-hardware-decommissioning).

Tank retirement is the preceding one-way lifecycle transition. It is serialized
with device writes, records retirement metadata and an audit event, forces the
tank private, clears `monitoring_expected_at`, resolves an active monitoring
incident as `tank_retired`, and deactivates every registered device in the same
transaction. The shared lifecycle service uses SQLite's writer lock during
development and row locks on PostgreSQL. Retired detail and history remain
readable, but live fleet/public/ingestion/control and active tank mutation paths
exclude or reject the retired record. A last-device transition resolves an
active incident as `monitoring_disabled`; the first active device after zero
starts a fresh expectation grace period.

Physical device movement is modeled as deactivation plus new provisioning. A
registered device's server-side tank mapping is never edited, and readings,
commands, and state history remain attached to the original identity. The
operator must physically move and verify the hardware, provision a new
destination registration and one-time key, confirm destination-only readings,
and recreate only intended device-resident schedules. See
[`docs/WORKFLOWS.md`](WORKFLOWS.md#moving-equipment-to-another-tank).

For actuator control, an admin queues a server-generated command for the fixed
device/tank mapping. The bridge fetches only unexpired commands using the
registered device key, claims one before making the matching allowlisted local
GET request, and reports `executing`, `succeeded`, `failed`, or
`outcome_unknown`. The bridge uses `failed` only for confirmed pre-dispatch or
explicit non-ambiguous rejection; post-dispatch timeout, lost/malformed
response, completion timeout, and state-poll failure are ambiguous and report
`outcome_unknown`. If the confirmation deadline expires from `executing_at`,
shared reconciliation persists terminal `outcome_unknown` rather than
expiring or retrying the command. A single process-local periodic maintenance
loop runs that same idempotent reconciler without requiring a browser request.
The backend records the admin actor, validated payload, queue and confirmation
deadlines, timestamps, result/error, physical-verification metadata, and
append-only state reports. Staff users receive 403 for actuator command, state,
and history endpoints.

The ESP32 bridge is temporary test infrastructure. It polls the local firmware
`/data` endpoint and forwards four installed sensors, then polls pending admin
commands through the backend. UV, normal LED, feeder, and manual-test-only
Syringe Pump A/B actions are allowlisted. Pump dispense sends the firmware's
exact `/syringeA/dispense` or `/syringeB/dispense` route once, then polls the
matching status route until the firmware-configured `volume_ml` move reports
complete. If completion is not observed before the bounded local safety
timeout, the bridge sends one intentional matching stop request. Hardware
calls are not automatically retried after an ambiguous response because the
actuator may already have run. The current firmware does not expose a
volume-setting route, so the dashboard displays the firmware-reported volume
and does not accept a fake millisecond dose value. Dissolved oxygen and
ammonia remain nullable/unavailable, are skipped by threshold evaluation, and
  have no actuator or command path.

   Same-device, same-pump dispense creation is serialized on the registered
   device row: PostgreSQL uses a row lock and SQLite development uses its
   `BEGIN IMMEDIATE` writer lock. The claim path repeats the active-pump check
   under the same serialization before the physical call. A pump uncertainty
   lock blocks only another dispense for that device and pump; Stop remains
   available, and administrator physical verification clears only the software
   lock without changing the historical unknown outcome. Late bridge reports
   receive a deterministic conflict and cannot rewrite the command.

The browser and backend never connect directly to the ESP32. Tunnel
infrastructure is limited to temporary dashboard/API testing; the ESP32 stays
on the tester's private Wi-Fi and is never exposed to the internet. Pump
schedules, pH auto-dose, and automatic dosing from sensor data remain outside
the command allowlist.

Species-care evaluation is a parallel read path: an authenticated tank drawer
loads the tank's assignments and one latest reading, then returns a dynamic
care result. It shares only the 90-second reading-freshness helper with the
decision engine; operational thresholds and persisted Alert records remain
separate.

The staff web surface separates the tank directory (`/admin/tanks`), the
administrator actuator chooser (`/admin/actuators`), the bookmarkable
operations workspace (`/admin/tanks/:tankId`), the dedicated
administrator actuator control center (`/admin/tanks/:tankId/actuators`), and
the shared configuration drawer (`?edit=`). The detail route owns live
operations and care polling, assignments, alert resolution, and a compact
actuator snapshot; the dedicated actuator route owns full controls, pump-test
safety prompts, and paginated command history. The chooser only selects a tank
view; both actuator surfaces reuse the same backend command boundary, and the
page routes do not replace backend authorization.

## Deployment direction

Local development uses the backend and Vite development server. `render.yaml`
contains the current Render API configuration, and `web/vercel.json` contains
the web proxy configuration, but cloud resources have not been provisioned or
fully validated. The intended production path is an explicit PostgreSQL
database, controlled CORS and trusted hosts, a unique JWT secret, disabled demo
generation, and a deployed web client. Production startup rejects unsafe
configuration rather than falling back to development defaults.

# AquaLogic Domain Model

Status: Current backend model summary
Last reviewed: 2026-09-26

## Entities

| Entity | Purpose | Important relationships |
| --- | --- | --- |
| User | Staff identity, role, active state, and password-change state | Resolves alerts; admin role controls staff and threshold writes |
| AuthSession | Revocable authenticated session | Belongs to a user; access JWT `sid` identifies the session |
| PushDevice | Android Firebase messaging registration for one app installation | Unique AquaLogic installation ID, optional Firebase Installation ID (FID), and separate FCM token; bound to the registering user and `AuthSession` |
| PushNotificationEvent | One logical operational notification in the backend outbox | Unique deterministic `event_key`; optional tank reference; versioned string-only FCM data |
| PushNotificationDelivery | Delivery state for one event and registered device | Unique `(event_id, push_device_id)`; tracks retries, lease, sanitized error code, and result |
| Customer | Customer or account associated with managed tanks | Owns zero or more tanks |
| Tank | Managed aquarium and public display metadata | May belong to a customer; has fish, readings, alerts, and optional monitoring-threshold overrides |
| FishSpecies | Grouped species-level identity, diet, care, compatibility, and customer-facing profile information | Assigned to tanks through `TankFish` |
| TankFish | Many-to-many tank/species assignment | Composite key of tank and fish species |
| SensorReading | Timestamped water-quality measurement with observation and server receipt times | Belongs to one tank; may retain a nullable source device; may produce alerts |
| ThresholdConfig | Global fallback bounds and unit per parameter | Used when a tank has no override for that parameter |
| ThresholdRevision | Append-only snapshot of a global threshold default and its effective timestamp | Supplies global fallback history for analytics |
| TankThresholdOverride | Complete tank-specific bounds and enabled state for one parameter | Replaces the full global configuration for that tank and parameter |
| TankThresholdRevision | Append-only tank override or reset event | Supplies effective historical analytics bands; reset events resume the global timeline |
| Alert | Persisted warning or critical condition | Belongs to a tank and optionally a reading; can be resolved by an operator or the monitoring engine |
| RegisteredDevice | Device-key identity fixed to exactly one tank | Authenticates the bridge, tracks last seen time, and supports admin activation/key rotation |
| ActuatorCommand | Admin audit and lifecycle record for one physical UV, LED, feeder, or guarded pump-maintenance command | Belongs to one registered device/tank and optionally an actor user |
| ActuatorState | Latest validated local state for one actuator | Unique per registered device and actuator; may be stale when the bridge is unavailable |
| ActuatorStateHistory | Append-only bridge state report | Belongs to one device/tank/actuator and may reference a command |
| MonitoringIncident | Tank-level interval where expected accepted reporting stopped | One unresolved row per eligible active tank; resolves automatically on accepted reporting, monitoring disablement, or retirement |

Species-care suitability is intentionally derived rather than persisted. For
each tank assignment, the approved evaluation compares the latest fresh reading
with configured temperature, pH, and TDS preferences. Its statuses are
`suitable`, `attention`, and `unavailable`; they are not Alert severities and
have no acknowledgement or history lifecycle. A legacy dissolved-oxygen field
may remain in stored species data, but it is excluded from the approved
suitability workflow.

## Sensor parameters

The current reading contract includes:

- `temperature`
- `ph`
- `turbidity`
- `dissolved_oxygen`
- `tds`
- `ammonia`

All six values are currently represented on a reading. Threshold configuration
controls whether each parameter participates in status and alert evaluation.
Disabled parameters are unavailable and do not create new alerts. Installed
bridge/manual inputs validate temperature `-10..60`, pH `0..14`, turbidity
`0..3000`, and TDS `0..5000`. `timestamp` is the observation time;
`received_at` is server-generated and is the freshness boundary. Deferred
dissolved oxygen and ammonia remain nullable compatibility fields and are hidden
from current bridge and user-facing workflows.

## Identity and visibility

- Internal numeric IDs are used in authenticated staff workflows.
- Tanks also have a `public_id`; public routes use this value instead of the
  internal tank ID.
- A public tank must have `is_public` enabled to be returned by the public API.
- Public responses contain display information, the reduced customer-safe fish
  species projection, the latest active sensor fields, parameter statuses, and
  public care notes; they must not expose staff-only management data.

## Alert lifecycle

```text
reading received -> thresholds evaluated -> active alert created or updated
                                      |              |
                                      |              ├─ normal same parameter -> system-resolved
                                      |              └─ operator action -> operator-resolved
                                      v
                              later abnormal period -> new incident
```

Alert severities are `warning` and `critical`. There is at most one active alert
per tank and parameter. Warning can escalate to Critical and Critical can
downgrade to Warning. A fresh normal value for the same parameter resolves the
alert; a missing value does not. Alert responses expose nullable
`resolution_source` (`operator` or `system`). Automatic resolutions are also
recorded as administrator-only `alert.auto_resolve` audit events.

## Operations and analytics

Fleet Overview is a staff/admin read-only projection of tank health, reporting
age, active alert counts, Species Care context, recent unresolved alerts, and
reporting uptime. Tank Workspace combines tank metadata, latest operational
reading, alert context, advisory Species Care, and authorized tank actions.
Neither view creates a separate history store.

Fleet analytics is a staff/admin read-only projection over temperature, pH,
turbidity, and TDS for supported web workflows. It preserves nullable timelines,
historical threshold revisions, alert events, previous-period comparisons, and
reporting diagnostics. Analytics groups readings, uptime intervals, and gaps by
server `received_at`; observation time remains historical context.

Public tank pages are read-only projections selected by public ID and public
visibility. They expose customer-safe tank metadata, the reduced species
projection, and active public sensor fields only. They do not expose alert
history, threshold configuration, assignment metadata, device data, or receipt
metadata.

Actuator schedules are device-resident configuration rather than backend
scheduler jobs. A schedule command is validated, queued, claimed by the fixed
bridge, and forwarded once to the ESP32. The device owns future execution;
AquaLogic stores the configuration command and latest reported state but does
not create a command for each autonomous event. Last-known actuator state does
not guarantee current physical state when the bridge is stale or offline.

Actuator command status is `queued`, `executing`, `succeeded`, `failed`,
`expired`, or terminal `outcome_unknown`. The unknown state is reached only
after an atomic claim when the 180-second post-claim confirmation deadline
passes; it is not queue expiry and is never replayed. A same-device,
same-pump `dispense` remains interlocked while executing or uncleared unknown.
Administrator physical verification records actor, time, and bounded note,
clears only the software lock, and does not rewrite the historical outcome.
Late bridge reports are rejected with `409 Conflict`.

Monitoring incidents are not water-quality Alerts. An active tank with at least
one active registered device becomes monitoring-expected at the first
zero-to-one device transition and keeps that expectation while any active
device remains. After the 900-second default unattended grace (strictly longer
than the 90-second Offline rule), the background detector persists one active
incident per tank. The baseline is the later of `monitoring_expected_at` and
the latest accepted `SensorReading.received_at`. An accepted reading resolves
the interval as `reporting_recovered` and records its reading ID; the last
device deactivation resolves it as `monitoring_disabled`; retirement resolves
it as `tank_retired`. These transitions are UTC/server-time based and produce
no manual resolution action or external notification.

## Invariants to preserve

- Tank names are unique.
- Fish species cannot be assigned to the same tank more than once.
- Fish species with tank assignments cannot be deleted.
- Species preferred temperature, pH, and TDS ranges are inclusive, may be
  one-sided, and may use equal endpoints; a minimum greater than its maximum is
  rejected.
- A tank's customer must exist when assigned.
- Deleting a customer preserves its tanks and clears their nullable customer
  reference.
- Only active users can authenticate.
- Users with temporary passwords must complete password change before accessing
  the main staff dashboard.
- A `PushDevice` installation belongs to one current user/session and its FCM
  token belongs to one registration. Only active devices for active `admin` or
  `staff` users with an unrevoked, unexpired bound session are eligible for
  delivery. Client payloads cannot choose the user or session.
- AquaLogic installation IDs are random per app install and are not hardware
  identifiers. Firebase Installation IDs and FCM tokens are distinct transport
  identifiers; both are omitted from ordinary API responses and application
  logs. FCM never grants AquaLogic access or becomes domain-state authority.
- A push event and eligible delivery rows are written by the caller's source
  transaction; Firebase network calls happen after that transaction. Delivery
  claims use leases and are rechecked against current active device, active
  admin/staff user, and unrevoked/unexpired bound session state. Transient
  retries are bounded; an unregistered Firebase recipient deactivates only the
  matching current FID or fallback FCM token. This is duplicate-resistant
  at-least-once delivery, not exact-once FCM transport.
- Only administrators can create/update staff accounts or write global defaults
  and tank threshold overrides; staff can read effective threshold settings.
- Only administrators can queue or read actuator commands and state; staff
  receives 403 for actuator command, state, and history APIs.
- A registered device's key maps to one server-side tank; device requests never
  supply an arbitrary tank ID. Physical movement follows the [canonical
  deactivation and move/reprovisioning workflow](WORKFLOWS.md#moving-equipment-to-another-tank);
  the fixed mapping and historical ownership are never edited.
- Sensor readings retain nullable `device_id` provenance and non-null
  server-generated `received_at`; manual readings have no source device.
- Operational freshness and latest-reading selection use `received_at` with a
  90-second window; observation timestamps remain historical diagnostics.
- Exact threshold boundaries are Normal, strict bound ordering is required, and
  global and tank threshold changes are prospective rather than retroactive.
- Each tank uses a complete override for a parameter when present, otherwise
  it inherits the current global default. Reset removes the override; no
  individual bound is merged with the other configuration. Tank override units
  are fixed from the global parameter unit.
- A fresh reading uses the worst severity among present, enabled values; missing
  values are Unavailable and a reading with no usable fresh value is Offline.
- Device connection status is derived as online, offline, or disabled from
  activation and the 90-second last-seen window. Multiple active devices per
  tank remain supported for the current release.
- A tank derives lifecycle from nullable `retired_at`: `active` when null and
  `retired` otherwise. Retirement records the administrator, bounded optional
  note, and timestamp; it is one-way in this release.
- Retirement forces the tank private, clears its monitoring expectation,
  deactivates every registered device in the same transaction, and preserves
  readings, alerts, assignments, configuration, media, actuator commands, and
  state history. The public projection and live fleet exclude retired tanks.
- Tank deletion is a second administrator-only action available only after
  retirement. It cascades dependent readings, alerts, assignments, registered
  devices, and actuator records, then removes an AquaLogic-owned local hero
  image after the database commit. External URLs and paths outside the
  configured media root are never treated as owned files.
- Tank retirement/deletion does not clear device-resident schedules, firmware
  configuration, or physical equipment state; hardware decommissioning is an
  operator workflow. Retirement is blocked by executing or uncleared unknown
  actuator work, and the administrator must follow the hardware checklist.
- A queued actuator command must expire before execution, and a device must
  claim it before any physical call. Final command reports are idempotent.
- Actuator actions are limited to UV, normal LED, feeder, and the explicit
  manual-test-only `pump_a`/`pump_b` contracts; pump schedules, pH auto-dose,
  and sensor-driven dosing are not domain actions.
- Normal actuator commands use a 120-second default expiry with a 300-second
  maximum; pump maintenance commands use a 20-second default with a
  30-second maximum. Ambiguous physical requests are not automatically retried.
- Every successful threshold update appends a revision in the same transaction;
  revisions are never edited in place. Tank reset history records a fallback
  event, after which effective history follows the global revision timeline.
- Species preferences never generate operational threshold overrides. Public
  responses may expose the resulting water status, but not numeric threshold
  configuration.
- Schema changes are represented by migrations, not only by local SQLite table
  creation.
- Legacy invalid species ranges safely evaluate as unavailable.

- Species compatibility is notes-only. Pairwise compatibility, stocking
  recommendations, and compatibility-based assignment blocking are deferred.

- Tank species assignment and removal are staff/admin operations recorded in the
  audit trail; assignment history remains audit-only.

The current release has tank retirement fields and a dedicated persistent
monitoring-incident entity. Monitoring incidents remain separate from Alert
rows and are never synthesized as water-quality parameters.

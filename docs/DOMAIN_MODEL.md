# AquaLogic Domain Model

Status: Current backend model summary
Last reviewed: 2026-08-21

## Entities

| Entity | Purpose | Important relationships |
| --- | --- | --- |
| User | Staff identity, role, active state, and password-change state | Resolves alerts; admin role controls staff and threshold writes |
| Customer | Customer or account associated with managed tanks | Owns zero or more tanks |
| Tank | Managed aquarium and public display metadata | May belong to a customer; has fish, readings, and alerts |
| FishSpecies | Grouped species-level identity, diet, care, compatibility, and customer-facing profile information | Assigned to tanks through `TankFish` |
| TankFish | Many-to-many tank/species assignment | Composite key of tank and fish species |
| SensorReading | Timestamped water-quality measurement with observation and server receipt times | Belongs to one tank; may retain a nullable source device; may produce alerts |
| ThresholdConfig | Configurable bounds and units per parameter | Used by the decision engine |
| ThresholdRevision | Append-only snapshot of a threshold configuration and its effective timestamp | Supplies historically correct analytics bands |
| Alert | Persisted warning or critical condition | Belongs to a tank and optionally a reading; can be resolved by an operator or the monitoring engine |
| RegisteredDevice | Device-key identity fixed to exactly one tank | Authenticates the bridge, tracks last seen time, and supports admin activation/key rotation |
| ActuatorCommand | Admin audit and lifecycle record for one physical UV, LED, or feeder command | Belongs to one registered device/tank and optionally an actor user |
| ActuatorState | Latest validated local state for one actuator | Unique per registered device and actuator |
| ActuatorStateHistory | Append-only bridge state report | Belongs to one device/tank/actuator and may reference a command |

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
- Only administrators can create/update staff accounts or write thresholds.
- Only administrators can queue or read actuator commands and state; staff
  receives 403 for actuator command, state, and history APIs.
- A registered device's key maps to one server-side tank; device requests never
  supply an arbitrary tank ID.
- Sensor readings retain nullable `device_id` provenance and non-null
  server-generated `received_at`; manual readings have no source device.
- Operational freshness and latest-reading selection use `received_at` with a
  90-second window; observation timestamps remain historical diagnostics.
- Exact threshold boundaries are Normal, strict bound ordering is required, and
  threshold changes are prospective rather than retroactive.
- A fresh reading uses the worst severity among present, enabled values; missing
  values are Unavailable and a reading with no usable fresh value is Offline.
- Device connection status is derived as online, offline, or disabled from
  activation and the 90-second last-seen window. Multiple active devices per
  tank remain supported for the current release.
- A queued actuator command must expire before execution, and a device must
  claim it before any physical call. Final command reports are idempotent.
- Actuator actions are limited to UV, normal LED, feeder, and the explicit
  manual-test-only `pump_a`/`pump_b` contracts; pump schedules, pH auto-dose,
  and sensor-driven dosing are not domain actions.
- Every successful threshold update appends a revision in the same transaction;
  revisions are never edited in place.
- Schema changes are represented by migrations, not only by local SQLite table
  creation.
- Legacy invalid species ranges safely evaluate as unavailable.

- Species compatibility is notes-only. Pairwise compatibility, stocking
  recommendations, and compatibility-based assignment blocking are deferred.

- Tank species assignment and removal are staff/admin operations recorded in the
  audit trail; assignment history remains audit-only.

# AquaLogic Domain Model

Status: Current backend model summary
Last reviewed: 2026-08-15

## Entities

| Entity | Purpose | Important relationships |
| --- | --- | --- |
| User | Staff identity, role, active state, and password-change state | Resolves alerts; admin role controls staff and threshold writes |
| Customer | Customer or account associated with managed tanks | Owns zero or more tanks |
| Tank | Managed aquarium and public display metadata | May belong to a customer; has fish, readings, and alerts |
| FishSpecies | Grouped species-level identity, diet, care, compatibility, and customer-facing profile information | Assigned to tanks through `TankFish` |
| TankFish | Many-to-many tank/species assignment | Composite key of tank and fish species |
| SensorReading | Timestamped water-quality measurement | Belongs to one tank; may produce alerts |
| ThresholdConfig | Configurable bounds and units per parameter | Used by the decision engine |
| ThresholdRevision | Append-only snapshot of a threshold configuration and its effective timestamp | Supplies historically correct analytics bands |
| Alert | Persisted warning or critical condition | Belongs to a tank and optionally a reading; can be resolved by a user |
| RegisteredDevice | Device-key identity fixed to exactly one tank | Authenticates the bridge and tracks last seen time |
| ActuatorCommand | Admin audit and lifecycle record for one physical UV, LED, or feeder command | Belongs to one registered device/tank and optionally an actor user |
| ActuatorState | Latest validated local state for one actuator | Unique per registered device and actuator |
| ActuatorStateHistory | Append-only bridge state report | Belongs to one device/tank/actuator and may reference a command |

Species-care suitability is intentionally derived rather than persisted. For
each tank assignment, the service compares the latest fresh reading with the
species' configured ideal temperature, pH, dissolved-oxygen minimum, and TDS
ranges. Its statuses are `suitable`, `attention`, and `unavailable`; they are
not Alert severities and have no acknowledgement or history lifecycle.

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

## Identity and visibility

- Internal numeric IDs are used in authenticated staff workflows.
- Tanks also have a `public_id`; public routes use this value instead of the
  internal tank ID.
- A public tank must have `is_public` enabled to be returned by the public API.
- Public responses contain display information, fish species, latest reading
  information, parameter statuses, feeding schedule, and care notes; they must
  not expose staff-only management data.

## Alert lifecycle

```text
reading received -> thresholds evaluated -> active alert created or retained
                                             |
                                             v
                                    staff resolves alert
```

Alert severities are `warning` and `critical`. Resolution records the resolved
state, timestamp, and resolving user where available. Any change to alert
deduplication or severity semantics must update the decision-engine tests and
`docs/DECISIONS.md`.

## Invariants to preserve

- Tank names are unique.
- Fish species cannot be assigned to the same tank more than once.
- Fish species with tank assignments cannot be deleted.
- A tank's customer must exist when assigned.
- A customer with assigned tanks cannot be deleted until those tanks are
  reassigned.
- Only active users can authenticate.
- Users with temporary passwords must complete password change before accessing
  the main staff dashboard.
- Only administrators can create/update staff accounts or write thresholds.
- Only administrators can queue or read actuator commands and state; staff
  receives 403 for actuator command, state, and history APIs.
- A registered device's key maps to one server-side tank; device requests never
  supply an arbitrary tank ID.
- A queued actuator command must expire before execution, and a device must
  claim it before any physical call. Final command reports are idempotent.
- Actuator actions are limited to UV, normal LED, feeder, and the explicit
  manual-test-only `pump_a`/`pump_b` contracts; pump schedules, pH auto-dose,
  and sensor-driven dosing are not domain actions.
- Every successful threshold update appends a revision in the same transaction;
  revisions are never edited in place.
- Schema changes are represented by migrations, not only by local SQLite table
  creation.
- Fish temperature, pH, and TDS preferred minimums must not exceed their
  preferred maximums. Legacy invalid ranges safely evaluate as unavailable.

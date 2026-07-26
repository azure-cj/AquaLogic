# AquaLogic Domain Model

Status: Current backend model summary
Last reviewed: 2026-07-27

## Entities

| Entity | Purpose | Important relationships |
| --- | --- | --- |
| User | Staff identity, role, active state, and password-change state | Resolves alerts; admin role controls staff and threshold writes |
| Customer | Customer or account associated with managed tanks | Owns zero or more tanks |
| Tank | Managed aquarium and public display metadata | May belong to a customer; has fish, readings, and alerts |
| FishSpecies | Species-level care and compatibility information | Assigned to tanks through `TankFish` |
| TankFish | Many-to-many tank/species assignment | Composite key of tank and fish species |
| SensorReading | Timestamped water-quality measurement | Belongs to one tank; may produce alerts |
| ThresholdConfig | Configurable bounds and units per parameter | Used by the decision engine |
| Alert | Persisted warning or critical condition | Belongs to a tank and optionally a reading; can be resolved by a user |

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
- A tank's customer must exist when assigned.
- A customer with assigned tanks cannot be deleted until those tanks are
  reassigned.
- Only active users can authenticate.
- Users with temporary passwords must complete password change before accessing
  the main staff dashboard.
- Only administrators can create/update staff accounts or write thresholds.
- Schema changes are represented by migrations, not only by local SQLite table
  creation.

# Data Integrity

## Status

**Current behavior plus hardening audit** — reviewed 2026-08-21.

This document records the integrity rules already implemented across the AquaLogic
domain and identifies areas that require verification or hardening. It does not
authorize schema changes without tests and migration review.

## Implementation checkpoint — 2026-08-21

SQLite foreign-key enforcement is enabled for both the application and test
engines through the shared connection configuration. Phase 06 coverage verifies
tank cascades, customer-reference nulling, reading/alert references,
device/tank and actuator relationships, composite assignment uniqueness, fish
deletion protection, duplicate values, and transaction rollback behavior.

This hardening pass added no new Alembic migration and no speculative database
`CHECK` constraints. Existing model/migration behavior remains the authority,
with service-level validation retained where no failing integrity case justified
a schema change. See [`backend/tests/test_data_integrity.py`](../../../backend/tests/test_data_integrity.py).

## 1. Purpose

Keep operational, access-control, sensor, alert, actuator, and media-related data
consistent across API requests, transactions, migrations, and recovery actions.

## 2. Actors

- **Staff/admin API caller:** Creates or updates permitted operational records.
- **Administrator:** Performs configuration, account, device, and actuator writes.
- **Device bridge:** Writes only through the fixed device boundary.
- **Decision engine:** Creates alerts from accepted sensor readings.
- **Migration operator:** Applies Alembic schema history.
- **Recovery operator:** Restores database/media state and validates the result.

## 3. Integrity Model

### Identity and access

- User email is unique and normalized before persistence.
- User role is limited to `admin` or `staff`.
- At least one active administrator must remain.
- Passwords, refresh tokens, and setup tokens are stored only as hashes.
- Sessions and refresh tokens are linked to their owning user/session and are
  invalidated through revocation, expiry, or token-version changes.

### Tanks and customers

- Tank name is unique.
- Public ID is unique and generated independently from the internal numeric ID.
- Tank code is unique when present and may be null.
- A tank may reference a customer; deleting a customer sets the tank reference to
  null rather than deleting the tank.
- Tank deletion cascades its dependent readings, alerts, assignments, devices,
  actuator commands, and actuator state records according to the model/migration
  contract.

### Fish and assignments

- A tank/species assignment is unique through the composite `tank_id` and
  `fish_species_id` key.
- Duplicate assignment attempts return `409`.
- A fish species with assignments cannot be deleted; assignments must be removed
  first.
- Preferred range ordering is validated before persistence.

### Sensor readings and alerts

- Every reading belongs to one tank.
- Required installed sensor values are non-null; deferred dissolved oxygen and
  ammonia values remain nullable.
- Reading timestamps are treated as UTC-aware values at API/service boundaries.
- Alerts reference a tank and may reference a reading; deleting a reading sets
  the alert's reading reference null.
- Alert resolution records resolved state, timestamp, and resolving user.
- Unresolved alert duplication is controlled by the decision-engine service, not
  by a database uniqueness constraint.

### Thresholds and analytics context

- Threshold parameter is unique in the current configuration table.
- Threshold revisions are append-only and retain effective timestamps.
- Analytics treats missing readings as missing data rather than zero values.
- Threshold updates and revision creation occur in one request transaction.

### Devices and actuators

- A registered device maps to one server-side tank.
- Device keys are stored as hashes and are never returned after provisioning.
- Browser actuator commands use a server-generated command ID, fixed device/tank
  mapping, validated payload, and expiry.
- Command lifecycle is bounded to `queued`, `executing`, `succeeded`, `failed`,
  or `expired`.
- Actuator state is unique per device and actuator; state history is append-only.
- Device-key command claims and final reports verify fixed device/tank ownership
  and are idempotent for already-finalized records.

### Uploaded media

- Tank and fish uploads use allowlisted content types, magic-header validation,
  bounded size, generated filenames, and a path confined to `MEDIA_ROOT`.
- A database commit failure removes the newly written file.
- Replacing a locally stored image removes the previous local file after the new
  database value is committed.
- Hosted URLs remain subject to the configured public-image policy.

## 4. States and Transitions

```text
fish unassigned ──assign──> assigned ──remove──> unassigned
alert unresolved ──resolve──> resolved
command queued ──claim──> executing ──report──> succeeded/failed
command queued ──expiry──> expired
session active ──revoke/expiry──> inactive
```

Invalid or duplicate transitions must return a controlled API error and must not
leave a partial audit or domain write committed.

## 5. Transaction Rules

- API write routes validate request schemas before opening domain transitions.
- Domain changes and their related audit records commit together.
- Routes flush when they need database-generated IDs or conflict detection before
  creating dependent records.
- Failed transactions roll back before the request returns an error.
- Physical actuator requests are never retried automatically after an ambiguous
  response; the command ledger remains the source of lifecycle truth.
- Alembic owns production schema changes. Development startup convenience
  creation must not replace migration validation.

## 6. Current Hardening Findings

- SQLite foreign-key enforcement is enabled through the shared application and
  test-engine connection configuration. Regression tests cover cascades,
  nullable references, relationship protection, and foreign-key checks.
- Several invariants are application-level rather than database `CHECK`
  constraints, including threshold ordering, alert resolution consistency, and
  device/tank consistency. Their service and API tests must remain authoritative
  until a database constraint is justified.
- Conflict handling should be regression-tested across all unique and composite
  key paths, not only tank creation and assignment.
- Fresh-database migration and upgrade-from-existing-database behavior must be
  tested for both access-security and actuator tables.

## 7. Main Workflows

### Protected domain write

1. Authenticate and authorize the caller.
2. Validate request schema and cross-entity references.
3. Apply domain changes and append the relevant audit record.
4. Flush when needed for constraint/error handling.
5. Commit as one transaction or roll back completely.

### Migration

1. Create/update the SQLAlchemy model and schemas.
2. Add an Alembic revision.
3. Upgrade a fresh temporary database.
4. Upgrade a representative existing database.
5. Run behavior tests against the migrated schema.

### Recovery integrity check

1. Restore a consistent database backup and media snapshot.
2. Apply migrations to the supported head.
3. Invalidate authentication sessions if the snapshot predates current access
   state.
4. Run health, login, public-tank, staff-read, and admin-write smoke checks.
5. Compare database references with restored media paths.

## 8. Edge Cases

- Duplicate tank names, duplicate assignments, duplicate emails, and duplicate
  device keys must not create partial records.
- Deleting a tank must not leave readable orphan readings, alerts, device states,
  or assignments.
- Deleting a customer must preserve tanks while clearing the customer reference.
- Deleting a fish species with assignments must be rejected.
- Replaying a finalized actuator claim/report must not execute or mutate the
  command incorrectly.
- A stale or missing reading must remain distinguishable from a zero reading.
- A failed media commit must not leave an orphaned uploaded file that the API
  advertises as current.
- Restoring only the database or only media can produce broken public/admin image
  references and must be treated as an incomplete recovery.

## 9. UI Behavior

- UI forms provide validation and confirmation for destructive or privileged
  actions, but backend validation remains authoritative.
- Conflict, validation, unavailable-device, and stale-state errors are shown as
  controlled notices rather than silent success.
- The UI must not infer that a stale actuator state means the physical device is
  off.

## 10. Backend Behavior

The primary integrity boundaries are the Pydantic schemas, route-level
cross-entity checks, SQLAlchemy models, Alembic migrations, decision engine,
actuator command service, and transaction/error handling in the route modules.

No backup or restore API exists in the current release. Recovery is an operator
workflow documented separately in `06-backup-and-recovery.md`.

## 11. Security / Permissions

- Authorization is checked before protected records are read or mutated.
- Public serializers expose privacy-safe fields and cannot be used to access
  staff-only identifiers or controls.
- Device ingestion cannot select an arbitrary tank.
- Audit records do not contain passwords, raw device keys, refresh tokens, setup
  tokens, or raw client IPs.

## 12. History / Audit

Important domain writes record actor, target, request, and outcome metadata where
the current route implements audit recording. Actuator command history and state
history are separate operational ledgers. Security audit history is a separate
administrator-only feed.

## 13. Acceptance Criteria

- Fresh and upgraded databases reach the same Alembic head without data loss.
- Foreign-key, uniqueness, cascade, and composite-key behavior is verified on
  SQLite and the PostgreSQL target before production release.
- All protected writes either commit domain and audit changes together or roll
  back together.
- Invalid state transitions and cross-entity references return controlled errors.
- No test or recovery workflow depends on committing a local database file to the
  repository.
- Restored database and media snapshots pass the documented smoke checks.

## 14. Open Decisions

- Which invariants should become database `CHECK` constraints rather than remain
  service-level validation.
- Production database backup retention, encryption, and restore ownership.
- Whether audit retention should differ by event category.

## 15. Deferred Scope

- Multi-region replication and failover.
- Event-sourcing all domain changes.
- Database-level analytics optimization for larger fleets.
- Automated repair of inconsistent historical records.

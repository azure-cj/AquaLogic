# Backup and Recovery

## Status

**Local operator capability implemented; production provider boundary remains**
— reviewed 2026-08-21.

This document defines the implemented local recovery boundary. It does not
claim that scheduled backups, cloud storage, provider configuration, or an
in-app restore flow exists in the application.

## Implementation checkpoint — 2026-08-21

The local operator boundary is implemented through the standard-library-only
modules [`backend/scripts/backup_local.py`](../../../backend/scripts/backup_local.py)
and [`backend/scripts/restore_local.py`](../../../backend/scripts/restore_local.py).
Backups package the transaction-safe SQLite copy and `MEDIA_ROOT` together in a
versioned timestamped archive. The manifest records the creation time, Alembic
revision, database checksum, media file list, and media checksums; environment
files, JWT secrets, credentials, and bridge configuration are excluded.

Restore is isolated-only and requires a new target directory. It rejects path
traversal and checksum failures, applies migrations, runs SQLite integrity and
foreign-key checks, preserves operational/media data, and increments restored
user token versions while revoking restored sessions. PostgreSQL backup and
point-in-time recovery remain deployment/provider responsibilities. Coverage is
in [`backend/tests/test_backup_recovery.py`](../../../backend/tests/test_backup_recovery.py).

## 1. Purpose

Protect AquaLogic operational data and uploaded media from local database loss,
deployment failure, accidental deletion, corruption, or restoration of an old
database snapshot.

## 2. Current Implementation

- Development defaults to a local SQLite database under `backend`.
- Production is configured for PostgreSQL through `DATABASE_URL`.
- Alembic owns production schema upgrades.
- Uploaded tank and fish images are stored under `MEDIA_ROOT`.
- `backend/scripts/backup_local.py` creates a transaction-safe, timestamped,
  checksummed SQLite-plus-media bundle.
- `backend/scripts/restore_local.py` validates a bundle, restores only into a
  new isolated directory, applies migrations, checks SQLite integrity, and
  invalidates restored sessions.
- No scheduled backup worker, backup API, restore API, backup dashboard, or
  provider backup provisioning exists in the application repository.
- No approved RPO, RTO, retention period, encryption standard, or recovery owner
  has been selected yet.

## 3. Actors

- **Local operator:** Creates and verifies local SQLite/demo backups.
- **Deployment operator:** Coordinates production backup and restore procedures.
- **Database provider:** Supplies PostgreSQL backup and point-in-time recovery
  facilities when configured.
- **Application administrator:** Validates restored login and application
  behavior but does not receive a browser backup-management feature in v1.

## 4. Data to Protect

### Database

Backups must include the complete application database, including:

- tanks, customers, fish, assignments, readings, alerts, and thresholds
- users, sessions, refresh/setup-token hashes, throttles, and security audit events
- registered devices, actuator commands, current state, and state history

### Media

Backups must include the contents and relative paths of `MEDIA_ROOT`, especially
uploaded tank hero images and fish photos.

### Configuration boundary

Environment files, JWT secrets, database credentials, device keys, and tunnel
configuration are not application backup payloads. They require separate secret
management and must never be committed with a backup artifact.

## 5. Recovery States

```text
not configured ──backup policy selected──> configured
configured ──successful backup──> backup available
backup available ──restore begins──> restore in progress
restore in progress ──checks pass──> restored and validated
restore in progress ──checks fail──> restore failed / rollback required
```

A backup is not considered usable merely because a file or provider snapshot
exists; it must be restorable and pass validation.

## 6. Business Rules

- **BR-BACKUP-001:** Database backups must represent a transactionally
  consistent database state.
- **BR-BACKUP-002:** Database and `MEDIA_ROOT` backups must be treated as one
  recoverable application state, with a documented consistency relationship.
- **BR-BACKUP-003:** Backup artifacts must be access-controlled and encrypted
  according to the approved production policy.
- **BR-BACKUP-004:** Backup artifacts must not contain environment secrets or
  unprotected raw device credentials.
- **BR-BACKUP-005:** A restore must never overwrite the live database or media
  directory; the local restore tool requires a new isolated target directory.
- **BR-BACKUP-006:** A restored database must be upgraded through the supported
  Alembic head before application validation.
- **BR-BACKUP-007:** Restoring an older database snapshot must invalidate or
  otherwise re-evaluate authentication sessions so old session state cannot be
  unintentionally resurrected.
- **BR-BACKUP-008:** Production recovery must not run demo seed workflows or
  enable demo sensor generation.
- **BR-BACKUP-009:** A restore is complete only after health, authentication,
  public-tank, staff-read, admin-write, and media-reference checks pass.

## 7. Recovery Workflows

### Local SQLite backup

1. Run `python -m scripts.backup_local --output-dir <backup-directory>` from
   `backend/`; optionally provide a file-backed `--database-url` and
   `--media-root`.
2. The script uses SQLite's backup API, packages the matching `MEDIA_ROOT`,
   records the Alembic revision and SHA-256 checksums, and writes a timestamped
   `aqualogic-backup-<UTC timestamp>.tar.gz` bundle.
3. Store the artifact outside Git and protect it as an operational secret.
4. Open and validate the bundle during a restore drill; a successful file copy
   alone is not a recovery test.

### Production PostgreSQL backup

1. Configure the production provider's managed backup or export facility.
2. Confirm that database backups and media storage have compatible retention and
   recovery points.
3. Restrict backup access to deployment/recovery operators.
4. Perform periodic restore drills in an isolated environment.

Application code should not duplicate provider-native PostgreSQL backup behavior
unless a deployment decision requires it.

### Restore drill

1. Select a known paired database/media bundle.
2. Restore it with `python -m scripts.restore_local --bundle <bundle>
   --target-dir <new-isolated-directory>`.
3. The script rejects an existing target and path traversal, verifies all
   checksums, applies Alembic migrations, and runs SQLite integrity checks.
4. The script revokes every restored authentication session and increments
   every restored user's token version.
5. Run the validation checklist against the isolated process.
6. Record success, failures, elapsed time, and missing artifacts externally.

## 8. Validation Checklist

- `/health` responds successfully.
- A known administrator can authenticate using the expected password policy.
- Existing restored users, roles, tanks, readings, alerts, thresholds, and
  actuator history are present.
- Public tank pages preserve privacy-safe fields and public visibility.
- Staff routes enforce the permission matrix.
- Administrator routes enforce the permission matrix.
- Restored media URLs resolve and no database-referenced media is missing.
- Device and actuator records retain fixed tank mappings.
- Demo generation remains disabled in production recovery.
- Old sessions are invalidated when required by the restore policy.
- The restored target is separate from the live database and media directory.

## 9. Edge Cases

- Database backup succeeds but media archive fails.
- Media archive succeeds but database backup is incomplete or corrupt.
- Backup schema is older than the current Alembic head.
- Restored database references a media file deleted after the backup.
- Restored media contains files no longer referenced by the database.
- An old snapshot resurrects users, sessions, setup tokens, or revoked actuator
  commands.
- Disk space or provider quota is insufficient during backup or restore.
- Restore validation succeeds for the database but fails for public privacy or
  authorization behavior.

## 10. UI Behavior

There is no backup or restore UI in the current release. The expected initial
interface is an operator runbook and, if needed, a local/deployment script. A
browser-accessible restore action is explicitly out of scope until authorization,
audit, destructive-action, and infrastructure requirements are approved.

## 11. Backend Behavior

The current backend exposes no backup or restore endpoints. The operational
interfaces are the standard-library-only `scripts.backup_local` and
`scripts.restore_local` modules. The existing health route and Alembic workflow
remain validation dependencies, not backup features.

## 12. Security / Permissions

- Backup and restore artifacts are operational secrets and must not be exposed to
  staff or public web clients.
- Restored database files must be protected like the live database because they
  contain password hashes, session data, audit metadata, and operational history.
- Restore access must be limited to an explicitly assigned deployment/recovery
  operator.
- A restore must account for authentication/session invalidation and revoked
  actuator commands before the system is reopened to users.

## 13. History / Audit

The application does not record backup or restore events in its security audit
feed. The operational workflow must retain an external record of backup
creation, verification, restore attempts, validation results, and the operator
responsible.

## 14. Acceptance Criteria

- A documented local backup can be created without committing artifacts to Git.
- A matching database/media backup can be restored in an isolated environment.
- A restored database can be migrated to the supported Alembic head.
- The validation checklist passes after restore.
- All restored authentication sessions are revoked and user token versions are
  incremented.
- Production backup ownership and provider responsibilities are documented before
  deployment is treated as production-ready.

## 15. Open Decisions

- Required recovery point objective (RPO).
- Required recovery time objective (RTO).
- Backup frequency and retention period.
- Encryption-at-rest and key-management policy.
- Recovery operator and approval process.
- Production media-storage strategy: persistent volume or object storage.
- Whether backup/restore events should later be mirrored into the administrator
  security audit feed.

## 16. Deferred Scope

- In-app backup management.
- In-app restore or rollback controls.
- Multi-region replication and automated failover.
- Cross-cloud backup orchestration.
- Customer-visible recovery status.

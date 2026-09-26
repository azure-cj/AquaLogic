# AquaLogic Development Workflows

Status: Current local workflow
Last reviewed: 2026-09-26

## First-time setup

### Backend

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\activate
pip install -r requirements-dev.txt
copy .env.example .env
alembic upgrade head
python -m seed.seed_data
```

The seed step above is for local development only. Do not run the demo seed
script in production.

The backend defaults to SQLite for development and tests. A production
environment must provide `DATABASE_URL` using PostgreSQL; a missing URL or a
SQLite URL fails settings validation at startup. The synchronous PostgreSQL
driver is installed from `requirements.txt`, and `postgres://` URLs are
normalized for SQLAlchemy.

### Production first administrator

After the production schema has been migrated, provide these one-off command
environment variables:

- `ADMIN_BOOTSTRAP_EMAIL`
- `ADMIN_BOOTSTRAP_PASSWORD` (12–128 characters)
- `ADMIN_BOOTSTRAP_NAME`

Run from `backend/`:

```powershell
python -m app.cli.create_admin
```

The command creates only the first administrator account (`admin` role), uses
the standard AquaLogic password hash, and makes no changes if the email or an
administrator already exists. It never prints the password. **Do not run the
demo seed script (`python -m seed.seed_data`) in production.**

### Firebase Admin push setup

M6.3 uses the Firebase Admin Python SDK on the Railway backend only. It requires
a Firebase service-account JSON key with permission to send FCM messages; the
Android `google-services.json` file is client configuration and cannot be used
as this server credential. Push remains disabled unless
`PUSH_NOTIFICATIONS_ENABLED=true` is explicitly set.

1. In the Firebase project, open **Project settings → Service accounts** and
   generate a private key for the Firebase Admin SDK service account, or use an
   existing least-privilege service account authorized to send Firebase Cloud
   Messaging messages. Enable the Firebase Cloud Messaging API (HTTP v1) and
   grant the service account the **Firebase Cloud Messaging API Admin** role or
   an equivalent least-privilege role containing
   `cloudmessaging.messages.create` ([Firebase send setup](https://firebase.google.com/docs/cloud-messaging/send/admin-sdk)).
2. Save the downloaded JSON outside the repository in a protected local
   location. Do not place it in Flutter, Vercel, source control, a ticket, or
   chat.
3. In PowerShell, encode the file in memory and copy the one-line result to the
   clipboard without printing it in the terminal:

   ```powershell
   $firebaseKeyPath = 'C:\secure\firebase-service-account.json'
   $firebaseKeyB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($firebaseKeyPath))
   Set-Clipboard -Value $firebaseKeyB64
   Remove-Variable firebaseKeyB64
   ```

   Base64 is only a transport encoding, not encryption. Paste the clipboard
   value directly into the Railway backend service variable
   `FIREBASE_SERVICE_ACCOUNT_JSON_B64`, marked as a secret. Optionally set
   `FIREBASE_PROJECT_ID` to the non-secret Firebase project ID for a consistency
   check. Then clear the clipboard with `Set-Clipboard -Value $null`; if
   Windows clipboard history is enabled, clear that entry through **Win+V** as
   well. Remove the downloaded key file according to your organization's
   key-handling policy.
4. Deploy the backend and verify Railway's normal pre-deploy migration path
   applies the outbox and FID migrations. The backend decodes the secret in
   memory only; it does not write the service-account JSON to disk. Keep
   `PUSH_NOTIFICATIONS_ENABLED` false during this verification when it is
   currently false. Check deployment health and
   `https://aqualogic-production.up.railway.app/health`. Then install the
   updated Android app and confirm an authenticated row has a FID without
   selecting or printing either Firebase identifier. Only a human should enable
   outbound push after these checks; do not start M6.4 until the deployed sender
   is healthy and a real Android installation has registered its FID.

Never use an FCM legacy server key or the Firebase client configuration file as
the backend credential. The Flutter client obtains FIDs through the official
`firebase_app_installations` plugin and observes `onIdChange`; it continues to
send the distinct FCM token for compatibility. The backend targets
`messaging.Message(fid=...)` whenever the row has an FID. The deprecated
`Message.token` target remains a compatibility fallback for pre-FID rows only
([Firebase Admin send documentation](https://firebase.google.com/docs/cloud-messaging/send/admin-sdk),
[Firebase Installations guidance](https://firebase.google.com/docs/projects/manage-installations)).

### Web

```powershell
cd web
npm install
```

### Mobile

```powershell
cd mobile_app
flutter pub get
```

## Daily local run

From the repository root:

```powershell
.\start-dev.bat
```

This starts the API at `http://127.0.0.1:8000` and the Vite web app at
`http://localhost:5173`, with the local-only demo sensor generator enabled.
It keeps the seeded fleet fresh with representative normal, warning, critical,
and offline states. API documentation is available at `http://127.0.0.1:8000/docs`.

For a temporary classroom demo from another laptop, double-click
`start-classroom-demo.bat`. It starts the local API and web app, waits for the
Vite server, checks that `ngrok` is installed, and exposes port `5173` through
an HTTPS ngrok URL. Keep all opened terminal windows running and prevent the
host computer from sleeping while presenting. This is a temporary tunnel, not
a production deployment.

For manual control, run the backend and web commands in separate terminals:

```powershell
cd backend
\.venv\Scripts\activate
python -m uvicorn app.main:app --reload
```

```powershell
cd web
npm run dev
```

When staff setup or password-reset links are generated, the backend uses
`PUBLIC_BASE_URL` as the browser URL. Keep the local default
`http://localhost:5173` when the recipient is using the same computer; for a
temporary classroom demo, set it to the active HTTPS web/tunnel URL before
creating the account link. Setup links are single-use and expire after 30
minutes, so generate a fresh link if an older one was opened or reset.

For the temporary ESP32 sensor/actuator bridge, follow
[`ESP32_BRIDGE_HARDWARE_TEST_RUNBOOK.md`](operations/hardware/ESP32_BRIDGE_HARDWARE_TEST_RUNBOOK.md).
Use the nested repository's owner/tester launcher files or run:

```powershell
python bridge\esp32_bridge.py --config bridge\bridge-config.json --once
python bridge\esp32_bridge.py --config bridge\bridge-config.json
```

The bridge configuration is local and untracked. The ESP32 URL must remain a
private local `/data` address; a temporary tunnel may carry only dashboard/API
traffic. The browser and backend never call the ESP32 directly.

## Tank deletion and hardware decommissioning

Tank retirement and permanent deletion are separate administrator workflows,
not remote hardware teardown. Retirement is the one-way `active -> retired`
transition: it makes the tank private, disables all registered devices in the
same transaction, clears its monitoring expectation, retains history/media, and
blocks on executing or uncleared-unknown actuator work. It is idempotent and
audited. Permanent deletion is available only after retirement and performs the
existing database-first relational/media cleanup. Retirement resolves any active
persistent monitoring incident as `tank_retired`; no new incident may open for
the retired tank.

Before retiring or permanently deleting a tank with registered equipment:

1. Identify every registered device and attached actuator for the source tank.
2. Keep the bridge online and physically inspect the correct hardware.
3. Disable device-resident schedules through the existing controls where safe.
4. Stop active equipment and verify the physical result locally.
5. Record any configuration that must be preserved for another tank.
6. Deactivate the old registered device/key in **Devices**.
7. Confirm no fresh readings or actuator commands are arriving under that
   identity.
8. Retire the tank only after hardware cleanup is complete. The retired detail
   remains available for historical review and offers the deliberate permanent
   delete action.
9. Permanently delete the tank only after the retired record and retained
   history/media have been reviewed.
10. If hardware is reused, follow [Moving equipment to another tank](#moving-equipment-to-another-tank) and provision a new registration for its
   destination.

The delete transaction takes the established tank lifecycle mutation lock, then
cascades the tank's sensor readings, alerts, species
assignments, registered devices, actuator commands, and actuator state history.
It also removes an AquaLogic-owned local uploaded tank hero image only after the
database commit succeeds. Missing files are harmless; external HTTPS image URLs
and paths outside the configured media root are never deleted. A post-commit
filesystem failure is logged for operator follow-up and does not roll back or
misreport the committed database deletion.

Database deletion does not clear ESP32 schedules, firmware configuration, or
physical actuator state. If the bridge or equipment cannot be reached, defer the
delete or record the unresolved physical follow-up explicitly; do not treat a
successful API response as proof of hardware cleanup.

## Moving equipment to another tank

Treat a physical move as a new provisioning event. This is the canonical
operator runbook for the [device-movement and reprovisioning hardening
packet](deep-spec/final-hardening/04-device-movement-and-provisioning.md). Do
not edit `tank_id`, move historical readings, reuse a device identity, or copy
raw keys:

1. Identify the source tank, registered device, and attached actuators.
2. Finish or physically verify pending actuator work. An executing or
   uncleared `outcome_unknown` pump command requires physical inspection and
   administrator verification before another same-pump dispense; **Stop**
   remains available during that lock.
3. Disable device-resident schedules and stop equipment where appropriate.
   Confirm the physical result locally; deactivation and database deletion do
   not clear firmware schedules or physical state.
4. Deactivate the existing device registration in **Devices**.
5. Stop or disconnect the old bridge configuration and confirm the old key no
   longer ingests readings or claims commands. The deactivated key returning
   `401` is expected, but does not prove the equipment stopped.
6. Physically move and reconnect the hardware. Confirm the destination tank,
   sensor wiring, actuator labels, pump A/B plumbing, and local power state.
7. Provision a new device registration for the destination tank as an
   administrator. Provisioning returns a new key once; it does not change the
   old device row or its historical ownership.
8. Configure the bridge with the new one-time key. The bridge has no tank
   selector; the server-side registration fixes the destination mapping. Keep
   the key out of logs, screenshots, tickets, and repository files.
9. Confirm the new identity reports **Online** and a fresh reading shows the
   new `device_id`, destination `tank_id`, server receipt time, supported units,
   and plausible values. Confirm no new source-tank reading is arriving under
   the old identity; identify any other active device explicitly.
10. Verify sensor identity and UV/LED/feeder/Pump A/B physical identity before
    controls resume. Treat last-known actuator state as diagnostic context, not
    physical confirmation.
11. Recreate only the intended device-resident schedules for the destination,
    then read back each device status. A successful schedule configuration
    request does not guarantee every future autonomous event.

The old registration remains inactive as the historical identity. If readings
appear on the source or on both tanks, stop the bridge and inspect its running
configuration rather than guessing which data is authoritative. If provisioning
fails, keep the old identity deactivated while the hardware is at the
destination. If the hardware is physically returned and fully verified, an
administrator may reactivate the old registration; a rotated old key must be
replaced with its one-time rotation response. A newly created destination
registration can be deactivated, but registrations and historical readings are
never merged.

Key rotation is a same-device credential replacement only. It invalidates the
previous key and returns the replacement once; it does not change `tank_id`,
move readings, or provision a destination identity. For the phase boundaries,
see the [Phase 01 monitoring-device spec](deep-spec/phase-01-domain-foundation/02-monitoring-device.md),
[bridge spec](deep-spec/phase-01-domain-foundation/03-bridge-architecture.md),
and [Phase 05 equipment connection spec](deep-spec/phase-05-equipment-control/01-equipment-connection.md).

## Validation workflow

Run the smallest check that proves the change, then the complete checks for the
affected application.

```powershell
cd backend
pytest -q
alembic upgrade head
pip-audit
```

```powershell
cd web
npm run typecheck
npm test
npm run build
npm audit --omit=dev
```

```powershell
cd mobile_app
flutter analyze
flutter test
```

For changes that affect public/admin behavior, also run the browser smoke or
visual regression workflow and preserve only intentional evidence under
`docs/evidence/browser-artifacts/`.

## Local backup and isolated restore

Local recovery is supported for file-backed SQLite only. From `backend/`, create
a paired database/media bundle outside the repository or under the ignored
`backend/backups/` directory:

```powershell
cd backend
python -m scripts.backup_local `
  --output-dir .\backups `
  [--database-url sqlite:///C:/path/to/aqualogic.db] `
  [--media-root C:\path\to\media]
```

The bundle contains `aqualogic.db`, `media/`, and a checksummed `manifest.json`.
It never packages environment files, JWT secrets, credentials, device keys, or
bridge configuration.

Restore only into a new, isolated directory:

```powershell
cd backend
python -m scripts.restore_local `
  --bundle .\backups\aqualogic-backup-<UTC timestamp>.tar.gz `
  --target-dir ..\restore\aqualogic-<UTC timestamp>
```

The restore command rejects an existing target, validates archive paths and
checksums, applies Alembic migrations, runs SQLite integrity checks, and
revokes every restored session while incrementing every restored user's token
version. There is no live-restore flag or HTTP restore endpoint. Start a
separate validation process with the restored database and media paths only
after the command completes.

Validate an isolated restore with `/health`, administrator login, staff read
access, administrator-only access, public tank privacy, restored media URLs,
and restored device/actuator mappings. Production recovery must not run demo
seeding or demo sensor generation.

Production PostgreSQL backups and point-in-time recovery remain the deployment
or database-provider responsibility. Production media storage must have a
compatible retention and recovery plan; the application does not duplicate
provider-native PostgreSQL backup automation.

## Database changes

1. Update the SQLAlchemy model and corresponding schema/service behavior.
2. Create a new Alembic revision from `backend/`.
3. Run `alembic upgrade head` against a fresh temporary database.
4. Add or update API tests for the behavior.
5. Do not edit or commit local `*.db` files as a substitute for a migration.

## API change workflow

1. Update backend schema/model/route behavior.
2. Update affected backend tests.
3. Update the web API models/client and UI consumers.
4. Check the Railway-backed mobile auth and operational-data clients, as well
   as any mock-only screens that still use local prototype data.
5. Update `docs/API_CONTRACT.md` and `docs/DEVELOPMENT_STATUS.md` if the public
   behavior or status changed.

## Documentation workflow

At the end of a meaningful task:

- Update the relevant area guide if structure or commands changed.
- Update architecture/domain/API docs if behavior or boundaries changed.
- Add a decision entry for cross-cutting choices.
- Update the status checkpoint only when implementation status changed.
- Keep task-specific notes in the task response or issue, not in permanent docs.

## Documentation validation

From the repository root, run the Markdown link checker after moving or adding
documentation:

```powershell
python scripts/check_markdown_links.py
git diff --check
```

Then confirm that current documents use the source-of-truth map in
`docs/INDEX.md`, historical material remains under `docs/history/`, and evidence
files are accompanied by a dated validation checkpoint. Search for stale paths,
task prompts, or superseded status language before committing:

```powershell
rg -n "Luna Extra High|implementation roadmap|WEB_DASHBOARD_IMPLEMENTATION_REPORT\.md|MOBILE_APP_DEVELOPMENT_PLAN\.md" docs README.md
```

## Deployment preparation

Deployment configuration is present in `render.yaml` and `web/vercel.json`, but
deployment is not complete. Before a production release, provide a PostgreSQL
`DATABASE_URL`, a unique 32-byte JWT secret, explicit CORS origins and trusted
hosts, a public base URL, controlled image hosts, and disabled debug/demo flags.
The backend code validates the database mode and migration URL handling, but the
production migration chain still needs a live PostgreSQL upgrade check. Verify
login, refresh rotation, public QR privacy, migration, headers, CORS, RBAC, and
sensor-ingestion smoke tests before release.

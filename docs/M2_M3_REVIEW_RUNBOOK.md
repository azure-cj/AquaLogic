# Isolated synthetic operator review

Last reviewed: 2026-10-02
Status: Local, opt-in review; real FastAPI computations and React UI.

From the nested AquaLogic repository in PowerShell:

```powershell
backend/.venv/Scripts/python.exe scripts/operator_review.py start
backend/.venv/Scripts/python.exe scripts/operator_review.py status
backend/.venv/Scripts/python.exe scripts/operator_review.py reset
backend/.venv/Scripts/python.exe scripts/operator_review.py stop
```

Existing backend `.venv` and web `node_modules` are required; no new dependency
is installed. `start` preserves existing review data; `reset` verifies and stops
only recorded review process identities, checks fixed database paths, removes
only dedicated review.db and known SQLite sidecars, and reseeds/restarts. No
recursive removal, normal database/media change or production seed occurs.
Windows child helpers run hidden and write `.operator-review/api.log` and
`web.log`. Process IDs, creation time and expected command marker protect stop
against PID reuse. Changed identities cause refusal, never a broad kill.

The launcher chooses available loopback API ports 8800–8899 and web ports
5180–5199, prints the actual URL, and binds both to 127.0.0.1. Initially:

- Login: `http://127.0.0.1:5180/admin/login`
- Clickable scenario index: `http://127.0.0.1:5180/api/synthetic-review`
- Admin: `admin@synthetic.example.com`
- Staff: `staff@synthetic.example.com`
- Synthetic password: `SyntheticReview2026!`

All these credentials exist only in the dedicated disposable local database.
The index and `.operator-review/scenarios.json` contain exact custom Analytics
windows, tank names/IDs, alert links, computed evidence/counts/qualifications,
and species context at reset. Use the generated links after each reset rather
than a previously copied dated URL. Reset may select different available ports.

Child environments inherit only operating-system/runtime paths, with explicit
local SQLite, media, API and development settings. No project/production env
file or credentials are loaded. Random generation, push dispatch and monitoring
incident generation are disabled; no devices or actuator commands are seeded.
The review API rejects device/bridge/actuator/push writes. Existing normal
production entry points and settings are unchanged. There is no public tunnel.
The React UI displays “Synthetic review data · Local API · No live aquarium
connection”; the API adds `X-AquaLogic-Data: synthetic-review`.

## Time and scenarios

Reset uses the actual current time. The explicit historical window ends at the
last completed clock half-hour and spans five hours. Standard scenarios have
40 observations at 0/5/10/15 minutes in each of ten half-hours. A separate latest
record outside that window supports fresh alert context. It expires after 90
seconds; reset and sign in again to inspect fresh species counts. Historical
custom-window Analytics remains reproducible after freshness expires. Browser
Refresh reloads data; it does not create a new reading. No clock freeze is used.

Species names beginning “Fictional” are invented synthetic profiles with
explicit test preferences, never claimed requirements for real species. Alert
records are deliberately seeded synthetic investigation/history scenarios;
normal historical values can coexist with such records. They do not represent
verified physical episodes. Existing suitability and monitoring behavior are
not changed by this review setup.

| Tank / primary metric | Expected primary finding in the five-hour window |
| --- | --- |
| 01 Up temperature / mixed species | Early 26.4, late 29.2°C; +2.8°C median change, +3.6°C fitted change; 24/40 within (60%); fresh species one within/one outside |
| 02 Down pH | Early 7.92, late 7.36; -0.56 median change, -0.72 fitted; 28/40 within (70%) |
| 03 Little change within range / temperature | 25°C, change 0; 40/40 within (100%) |
| 04 Little change outside range / temperature | 31°C, change 0; 0/40 within (0%); no health/recovery claim |
| 05 Repeated turbidity records | 12 NTU, 0/40 within; exactly three created records, two handled; retained individual links; species comparison unsupported |
| 06 Missing species preferences / TDS | 180 ppm, 40/40 within; one assigned species, zero evaluable, one unavailable |
| 07 Sparse / temperature | 20 observations, two timestamps per half-hour; direction/little change and within-range finding suppressed |
| 08 Noisy / temperature | 36/40 within (90%); temperature direction and little change suppressed with limitation |
| 09 Threshold revision / temperature | 29°C, little change; 20/40 within (50%), override expands 28 to 32°C halfway; revision disclosure |
| 10 Delayed / temperature | Same temperature historical result as 01, 40 delayed observations; latest observation deliberately old despite fresh receipt, species comparison unavailable |
| 11 Stale receipt / temperature | Historical 25°C, 100% within, little change; latest receipt five minutes old, current species comparison unavailable |
| 12 Retired historical context / temperature | Retained handled alert, stored preferences and retired lifecycle; no handling; authenticated Analytics API evidence available, existing web chooser remains active-tank-only |

Unchanged parameters can produce additional within-range/little-change cards.
Order puts lowest within-range percentage first, then repeated records,
directions and little change; expand the remainder to inspect direction cards.
The manifest records all cards and limitations, including those parameters.
Fleet totals remain fleet-wide even when an individual tank is selected.

Suggested inspection: open the index, sign in through tank 01's alert, compare
linked/latest timestamps and current species counts, expand its individual
preferences, follow Analytics, expand the increasing-temperature finding, then
inspect stable-outside, recurrence, sparse/noisy, revision and delayed cases.
Use staff login as a separate role check; equipment permissions remain existing.
Handling acknowledges a response and does not prove recovery. Reset discards
only this synthetic review state and invalidates its sessions.

## PostgreSQL validation checkpoint

One opt-in integration test passed against a newly initialized disposable
PostgreSQL 18 cluster on loopback 55432, using the installed tools under
`C:/Program Files/PostgreSQL/18/bin`. It covered real admin/staff authentication,
current/delayed species context, streamed Analytics, historical tank override
bounds, recurrence and retired context/handling guards. Test metadata was
created only in an empty dedicated `operator_guidance_test` database, dropped
on completion, and the disposable cluster was stopped. The existing PostgreSQL
service and the SQLite review server were untouched. This is targeted isolated
runtime evidence, not a full PostgreSQL suite or Railway smoke test.

The optional test is `backend/tests/test_operator_guidance_postgres.py`. It skips
without explicit `AQUALOGIC_TEST_POSTGRES_URL` and
`AQUALOGIC_TEST_POSTGRES_DISPOSABLE=1`, and refuses hosts/users/database names
outside its guarded synthetic boundary. It can be repeated only after explicitly
starting that dedicated cluster; the normal review launcher does not start it.

## Separate production smoke checks (not performed here)

After an independently authorized staged release:

1. Confirm Railway still uses PostgreSQL and Vercel `/api` still rewrites to
   Railway. No migration is needed for these additive response fields.
2. Read an existing alert context as staff/admin. Confirm absent-field client
   compatibility before API rollout and correct current preferences after it.
3. Read an existing custom Analytics window. Confirm observation buckets,
   receipt-based reporting, Refresh/successful-update time and named tank scope.
4. Compare within-range evidence against known effective threshold revisions;
   confirm delayed, sparse and unsupported evidence is qualified/unavailable.
5. Check real alert references and staff access without creating alerts or
   commanding equipment. Run PostgreSQL-backed integration checks in a separate
   isolated test database before treating SQLite checks as production evidence.
6. Perform physical Android push-tap verification only in its separately
   authorized device workflow. It remains pending from M1.

Mocks and this local review do not establish production or hardware validation.

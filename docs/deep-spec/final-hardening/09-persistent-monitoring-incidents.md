# Persistent Unattended Monitoring Incidents

Classification: **Owner-approved implemented work**  
Status: Implemented in backend/web/migration; bounded deployment validation remains operational work  
Last reviewed: 2026-08-22

## Objective

Persist a reviewable in-app incident when an active tank that is expected to be
monitored stops producing accepted readings while nobody is using the
dashboard.

Keep two deliberately different clocks:

```text
No fresh accepted reading for more than 90 seconds
-> request-time tank status is Offline

No accepted reading for 15 minutes by default
-> background detector persists one monitoring outage incident
```

The 90-second freshness rule remains unchanged. The persistent grace period is
configurable and defaults to 900 seconds.

## Why this is a separate incident type

Existing water-quality alerts represent abnormal parameter values and dedupe by
tank/parameter. A reporting outage has no abnormal parameter value, different
opening/recovery semantics, and may exist while no browser is open.

Use a dedicated `MonitoringIncident` model/API contract rather than inserting a
synthetic temperature/pH alert or overloading `Alert.parameter`. The web may
present both in the operational Alerts area, but terminology and types must
remain distinct.

## Incident identity and lifecycle

One active monitoring outage may exist per eligible tank:

```text
monitoring expected + reporting within grace -> no active incident
monitoring expected + grace exceeded -> active incident
active incident + fresh accepted reading -> resolved: reporting_recovered
active incident + tank retired -> resolved: tank_retired
active incident + all devices deactivated -> resolved: monitoring_disabled
```

Recommended persisted fields:

| Field | Meaning |
| --- | --- |
| `id` | Server-generated primary key |
| `tank_id` | Owning tank, cascade only on deliberate permanent deletion |
| `started_at` | When reporting first became absent: last receipt or expectation start |
| `detected_at` | When the background detector persisted the incident |
| `last_reading_received_at` | Snapshot of the last accepted receipt time, nullable for never-reported tanks |
| `resolved_at` | Terminal time, null while active |
| `resolution_reason` | `reporting_recovered`, `monitoring_disabled`, or `tank_retired` |
| `recovery_reading_id` | Nullable reading that proved recovery, with safe delete behavior |

The API may derive `is_resolved` from `resolved_at`. Do not add manual “Resolve”
or “Mark handled” behavior in the first pass: a reporting incident represents a
factual interval and should close automatically when monitoring recovers or is
intentionally disabled.

Enforce one active row per tank at the database boundary with a portable,
tested uniqueness strategy. A partial unique index on unresolved rows is
acceptable if the Alembic migration defines and validates both SQLite and
PostgreSQL forms. Application checks alone are insufficient under multiple
workers.

## Monitoring expectation eligibility

An incident may open only when all are true:

- the tank is active, not retired;
- the tank has at least one active registered monitoring device;
- monitoring expectation has been active continuously for the configured grace
  period;
- no accepted reading for the tank has been received within that grace period.

Do not open incidents for:

- retired tanks;
- tanks with no registered active device;
- tanks whose final active device was intentionally deactivated;
- the short interval immediately after first provisioning/reactivation;
- rejected/invalid sensor payloads merely because a bridge request occurred.

### Expectation timestamp

Persist an explicit `monitoring_expected_at` timestamp on the tank or in a
small dedicated expectation record. Set it when the tank transitions from zero
active devices to at least one active device. Clear it when the last active
device is deactivated or the tank is retired. Do not infer it solely from
`RegisteredDevice.created_at` or stale `last_seen_at`, because reactivation
would otherwise create an immediate false incident.

When a tank is eligible, the outage baseline is:

```text
max(monitoring_expected_at, latest accepted SensorReading.received_at)
```

An incident opens when `now - baseline >= grace`.

Device provisioning/activation/deactivation routes and retirement must update
expectation state transactionally. Multiple active devices keep monitoring
expected until the last one is disabled.

## Background detector

Implement one small idempotent service function that accepts an evaluation time
and database session. It must:

1. select eligible active tanks and their latest accepted receipt time;
2. calculate the baseline and grace deadline in UTC;
3. create one incident only after the deadline;
4. tolerate concurrent detector execution without duplicate active incidents;
5. commit or roll back each detector cycle predictably;
6. log counts/errors without sensor values, credentials, or private URLs.

Run it from a lightweight periodic background task owned by backend lifespan or
an equally small deployment process. Recommended initial interval: 60 seconds.
The implementation plan must account for multiple API workers: correctness must
come from idempotent database transitions/uniqueness, not an assumption that
only one process exists.

Configuration should include validated settings equivalent to:

```text
MONITORING_INCIDENTS_ENABLED=true
MONITORING_OUTAGE_GRACE_SECONDS=900
MONITORING_INCIDENT_CHECK_INTERVAL_SECONDS=60
```

The grace must be strictly greater than the 90-second reading-freshness window.
Production configuration and docs must not silently disable the feature after
it is considered implemented.

## Recovery integration

Every accepted manual or device reading already flows through shared decision
engine ingestion. After the reading is persisted successfully, resolve the
tank's active monitoring incident in the same transaction where practical:

- set `resolved_at` to the accepted server receipt time or current server time,
  chosen consistently and documented;
- set `resolution_reason = reporting_recovered`;
- record the recovery reading ID;
- emit one audit event without a human actor;
- do not resolve on rejected, invalid, or rolled-back readings;
- repeat processing must be idempotent.

Recovery does not mean water quality is Normal. The same reading may recover
reporting while creating/updating Warning or Critical water alerts.

## API contract

Provide authenticated staff/admin read access with bounded pagination and
filters. A suitable shape is:

```text
GET /monitoring-incidents
  ?tank_id=
  &state=active|resolved|all
  &started_after=
  &started_before=
  &page=1
  &page_size=25

GET /tanks/{tank_id}/monitoring-incidents
```

Default global state should be `active` for operational use; the history UI can
request `all`. Responses should expose tank identity/name, interval timestamps,
last receipt context, state, duration/age inputs, and resolution reason. Do not
expose device keys or private bridge data.

Fleet summary may add an active monitoring-incident count, but the existing
derived Offline status remains authoritative for current freshness. Avoid
creating a second competing “current tank status.”

## In-app UI requirements

### Fleet

- Continue showing Offline after 90 seconds.
- If a persistent incident exists, show a clear “Monitoring outage recorded”
  marker or count without replacing the Offline state.
- Last-known/reporting-age wording from packet 03 remains applicable.

### Alerts/incident history

- Present Monitoring outages as a distinct type/section or clear filter in the
  authenticated operational history.
- Do not label the incident as a water-quality alert.
- Show tank, outage start, detection time, last report, current duration or
  recovery time, and automatic resolution reason.
- No manual Resolve/Mark handled action in the first pass.

### Tank workspace

- Show the active outage incident and its start/age when present.
- Preserve last-known values as context.
- A recovered incident remains available in history but no longer appears as
  active.

No push, email, SMS, browser notification, sound, or on-call workflow is
authorized.

## Interaction with retirement and devices

- Retired tanks are ineligible for new incidents.
- Retirement resolves an active incident as `tank_retired`.
- Deactivating the last active device clears monitoring expectation and resolves
  an incident as `monitoring_disabled`.
- Deactivating one of several active devices does not close a tank-level
  incident if monitoring remains expected.
- Provisioning/reactivating the first active device starts a fresh grace period.
- Device heartbeat without an accepted reading does not prove sensor reporting
  recovery.

## Current implementation

The contract is implemented with migration `0013_persistent_monitoring_incidents`,
the dedicated `MonitoringIncident` model, the tank `monitoring_expected_at`
boundary from packet 08, a lifespan-owned detector, accepted-reading recovery,
and staff/admin paginated routes. A partial unique index on unresolved rows
enforces one active incident per tank across SQLite and PostgreSQL workers.
The web shows separate fleet markers, outage history, and tank-scoped history;
water-quality alerts and the 90-second Offline state remain separate.

## Likely implementation surfaces

| Layer | Likely files/areas |
| --- | --- |
| Model/migration | new monitoring incident model, tank expectation field/record, Alembic migration |
| Configuration/runtime | `backend/app/config.py`, `backend/app/main.py`, new focused monitoring service |
| Detection/recovery | new service plus shared reading ingestion integration |
| Device/tank lifecycle | provisioning activation/deactivation and packet-08 retirement service |
| API/schema | new schemas/routes with staff authorization and pagination |
| Web | shared API models, fleet, Alerts/history, tank workspace, styles/tests |
| Tests | monitoring engine/device/tank/permissions plus new worker/incident tests |
| Docs | architecture, API contract, domain model, development status, workflows, Phase 02/04 specs |

## Required backend tests

- grace configuration defaults to 900 and rejects values at/below freshness;
- eligible tank below grace creates no incident;
- detector creates one incident at/after grace;
- repeated and concurrent detector runs do not duplicate active incidents;
- a tank with no active device creates no incident;
- a newly provisioned/reactivated first device gets a full grace period;
- multiple devices still produce one tank-level incident;
- an accepted reading resolves the incident with recovery reading and audit;
- an invalid/rejected/rolled-back reading does not resolve it;
- recovery reading may also create a water alert without conflict;
- last-device deactivation resolves with `monitoring_disabled`;
- one-of-many device deactivation does not incorrectly disable monitoring;
- retirement resolves with `tank_retired` and prevents new incidents;
- pagination, filters, permissions, and tenant/tank scoping are correct;
- worker restart preserves active incidents and remains idempotent;
- timestamps use UTC/server receipt semantics;
- permanent tank deletion cascades incidents only after retirement.

Use a controllable evaluation clock in service tests; do not rely on real sleeps.

## Required web tests

- Offline appears at the existing freshness boundary independently of incident
  persistence;
- fleet marks an active recorded outage without hiding last-known data;
- incident history distinguishes monitoring outages from water alerts;
- active and recovered durations/reasons render correctly;
- no manual resolution or external-notification claim is shown;
- tank workspace shows active incident context;
- responsive layouts remain usable.

## Operational validation

In addition to automated tests, run a bounded local scenario:

1. configure a short non-production grace greater than 90 seconds;
2. provision/activate a device and accept a reading;
3. stop readings without opening the dashboard;
4. verify exactly one incident is persisted by the background detector;
5. restart the backend and verify no duplicate appears;
6. accept a new reading and verify automatic recovery;
7. repeat with retirement and last-device deactivation.

Record the result in `docs/DEVELOPMENT_STATUS.md`.

## Acceptance criteria

- AquaLogic records an unattended outage without a browser request.
- The existing 90-second Offline rule remains unchanged.
- One active incident exists per eligible tank after the 15-minute default
  grace, regardless of device count or worker count.
- Fresh accepted data resolves the incident automatically without claiming
  water conditions are Normal.
- Retirement and intentional monitoring disablement close/prevent incidents
  with distinct reasons.
- Staff can review active and recovered incidents in-app.
- No external notification or enterprise monitoring infrastructure is added.

## Non-goals

- Push, email, SMS, browser push, sounds, escalation, or on-call routing.
- Per-device outage incidents in the first pass.
- Replacing analytics reporting-gap reconstruction.
- Replacing the 90-second live Offline calculation.
- Enterprise job queues, observability platforms, or high-availability
  orchestration beyond idempotent database correctness.

## Luna Extra High goal prompt

```text
You are working in the current AquaLogic repository. Implement Goal 5 only:
owner-approved persistent unattended monitoring incidents.

Read AGENTS.md, docs/INDEX.md, docs/DEVELOPMENT_STATUS.md, docs/DECISIONS.md, the
final-hardening hub, packets 03, 08, and 09, relevant Phase 01/02/04 specs,
canonical architecture/domain/API/workflow docs, backend/web area guides, and
git status. Confirm the retired-tank lifecycle contract is stable before
implementation because incident eligibility depends on active versus retired.

Inspect current tank/device models and lifecycle routes, shared reading
ingestion, freshness helpers, backend lifespan/configuration, alerts/fleet/tank
APIs and UI, analytics gaps, permissions, tests, and deployment assumptions.
Produce a file-level plan first that locks:
- a dedicated MonitoringIncident model rather than synthetic water alerts;
- explicit monitoring expectation state and zero-to-one/one-to-zero active
  device transitions;
- one active incident per eligible active tank with database concurrency safety;
- 900-second default grace strictly greater than the 90-second Offline rule;
- an idempotent 60-second background detector safe under multiple workers;
- recovery only from a successfully accepted reading;
- monitoring_disabled and tank_retired terminal reasons;
- authenticated paginated API and distinct in-app fleet/history/tank UI;
- restart, UTC clock, migration, configuration, test, and documentation behavior.

Implement the plan end to end. Keep current request-time Offline behavior and
analytics gap reconstruction. Do not resolve an incident on heartbeat or an
invalid reading, and do not claim reporting recovery means water quality is
Normal. Add no manual resolution in the first pass. Do not add push, email, SMS,
browser notification, on-call routing, per-device incidents, enterprise queues,
or observability platforms.

Use controllable clocks rather than sleeps in automated tests. Run focused
detector/recovery/concurrency/lifecycle/API/UI tests, the bounded restart
scenario, full backend tests, Alembic validation, and web typecheck/tests/build.
Update architecture, domain, API, workflows, development status, and affected
phase docs. Finish with changed files, configuration/migration evidence,
validation results, acceptance criteria, and any deployment caveat.
```

# Retired Tank Lifecycle

Classification: **Owner-approved implemented work**  
Status: Implemented in backend/web/migration; packet 09 incident persistence is integrated  
Last reviewed: 2026-08-22

## Objective

Allow JRed to remove a physical tank from live operations without destroying
its historical readings, alerts, species assignments, device records,
equipment commands/state history, configuration, or tank media.

This is a two-state lifecycle, not a generalized archive system:

```text
active --administrator retires--> retired
retired --administrator permanently deletes--> deleted
```

Reactivation is not part of the first pass.

## Current behavior to replace carefully

Tanks currently have no lifecycle field. Authenticated list, fleet, operations,
species-care, public, sensor, assignment, device, and actuator routes generally
assume every existing tank is active. `DELETE /tanks/{tank_id}` immediately
hard-deletes the tank and cascades its operational records.

The existing cascade remains useful for deliberate permanent deletion, but it
is no longer the normal way to remove a tank from service. The implementation
uses migration `0012_retired_tank_lifecycle` and central lifecycle guards.

## Persistence contract

Preferred minimal additive fields on `tanks`:

| Field | Type | Meaning |
| --- | --- | --- |
| `retired_at` | nullable timezone-aware datetime | Null means active; value means retired |
| `retired_by_user_id` | nullable FK to `users.id`, `ON DELETE SET NULL` | Administrator who retired the tank |
| `retirement_note` | nullable bounded text/string | Optional operational reason, not required |

Derive lifecycle status as `active` or `retired` from `retired_at`; do not store
a second redundant boolean. Add an index supporting active-list filtering.
Existing rows migrate as active with all retirement fields null.

Use a new Alembic migration. Validate both a fresh database and an existing
database upgraded from the current head.

## Retirement endpoint

Use a dedicated administrator-only lifecycle endpoint rather than hiding the
transition inside the generic tank update contract. Preferred shape:

```text
POST /tanks/{tank_id}/retire
body: { "note": "optional bounded reason" }
```

Required semantics:

1. return `404` for a missing tank;
2. require administrator authorization;
3. if already retired, return the current retired representation without
   repeating side effects or audit events;
4. reject retirement while an actuator command for the tank is `executing` or
   `outcome_unknown` and uncleared;
5. set retirement metadata and force `is_public = false`;
6. deactivate every registered device for the tank in the same transaction;
7. clear `monitoring_expected_at` and resolve any active monitoring incident as
   `tank_retired` in the same transaction;
8. record one audit event containing tank ID and non-sensitive lifecycle facts;
9. preserve all historical relational rows and owned media;
10. return a tank representation that exposes lifecycle state and retirement
    metadata appropriate to the caller.

Do not send device commands automatically during retirement. The administrator
must follow the hardware decommissioning runbook before making the transition.
Retirement records database intent; it does not prove physical schedules or
equipment state were cleared.

## Active/retired query behavior

### Tank directory

The authenticated tank list should default to active tanks so current workflows
remain uncluttered. Add an explicit validated filter, for example:

```text
GET /tanks?lifecycle=active     (default)
GET /tanks?lifecycle=retired
GET /tanks?lifecycle=all
```

Staff and administrators may view retired tank details and history. Public
users may not.

### Fleet and live operations

- `/fleet` excludes retired tanks.
- Live fleet counts and analytics tank selectors exclude retired tanks by
  default.
- Historical analytics must continue to retain retired tank readings. If an
  authenticated historical selector needs retired tanks, provide an explicit
  include-retired path rather than erasing their data.
- Retired tank detail must display a prominent read-only Retired state and the
  retirement timestamp.

### Public page

Retirement sets `is_public = false`. The public lookup must return the existing
not-found/private behavior immediately. Do not expose a “retired tank” public
status unless separately approved.

## Read-only boundary after retirement

Retired tanks are historical records. Reject operational mutations with a
stable `409 Conflict` or other consistently documented domain response:

- manual sensor reading creation;
- device ingestion associated with the tank;
- new/changed registered devices or reactivation of its devices;
- actuator command creation;
- species assignment/removal;
- operational tank configuration edits, public visibility changes, and media
  replacement;
- any future workflow that would imply the tank is live.

Historical reads remain allowed to authenticated staff according to current
permissions. Security audit access remains administrator-only.

The implementation plan must centralize the active-tank guard in a small
service/helper rather than copy inconsistent checks across routes.

## Permanent deletion after retirement

Change hard deletion into a second, deliberate action:

- active tanks cannot be permanently deleted; return a stable conflict that
  directs the administrator to decommission and retire first;
- only administrators may permanently delete a retired tank;
- the expanded warning must enumerate relational history and owned local media;
- use the safe database-first local-media cleanup in packet 02;
- security audit events continue to survive through plain identifiers;
- no undelete or restoration is implied.

The UI should make Retire the normal destructive lifecycle action. Permanent
delete belongs in the retired detail/history surface and must not be styled as a
routine operation.

## UI requirements

### Active tank

- Administrator sees a confirmation-gated Retire action.
- Confirmation states that the tank leaves live operations, public access and
  registered devices are disabled, and history is retained.
- Link the hardware decommissioning checklist.
- If actuator uncertainty blocks retirement, show the backend reason and route
  the administrator to physical verification.

### Retired tank directory/history

- Provide an explicit Active/Retired filter or tabs.
- Retired rows are visually distinct but readable.
- Detail is read-only and shows retirement time, actor when available, note,
  prior configuration, species, readings/analytics, alert history, and
  equipment history that existing APIs can safely expose.
- Do not show live status as Offline; use Retired as the lifecycle state and
  label the last reading as historical/last known.
- Hide or disable operational controls with an explanation.
- Permanent deletion uses the stronger packet-02 warning.

## Interaction with devices and monitoring incidents

- Retirement deactivates all registered devices transactionally and clears the
  explicit monitoring expectation.
- Device keys fail authentication after deactivation as they do today.
- A retired tank can never open a new monitoring incident. Retirement resolves
  an active incident with the terminal reason `tank_retired` in the same
  transaction.
- Device movement to another tank still requires a new registration and key;
  retirement does not reassign devices.

## Likely implementation surfaces

| Layer | Likely files/areas |
| --- | --- |
| Model/migration | `backend/app/models/tank.py`, `backend/alembic/versions/` |
| Schema/API | `backend/app/schemas/tank.py`, `backend/app/routes/tanks.py` |
| Cross-route guards | sensors, devices/actuators, assignments, public, dashboard/analytics routes or a shared service |
| Audit | existing `audit_event` integration |
| Web models/routing | `web/src/shared/api/models.ts`, tank directory/detail/editor, fleet/analytics selectors |
| Tests | tank, integrity, permissions, media, device ingestion, actuators, public, analytics, web tank/fleet tests |
| Canonical docs | domain model, API contract, architecture, workflows, Phase 01/04/05 deep specs |

The implementation agent must confirm every route that can mutate or publicly
project a tank before finalizing its plan.

## Required backend tests

- migration preserves all existing tanks as active;
- administrator can retire an active tank;
- staff/public/device identities cannot retire a tank;
- repeat retirement is idempotent and does not duplicate audit events;
- retirement retains readings, alerts, assignments, devices, commands, state
  history, configuration, and hero media;
- retirement disables public access and every registered device;
- fleet/default tank lists exclude retired tanks;
- explicit retired/all list filters return authorized history;
- retired details remain readable to staff/admin;
- manual/device readings and operational writes are rejected after retirement;
- actuator commands and device reactivation are rejected;
- the retirement boundary clears monitoring expectation and resolves any active
  packet-09 incident as `tank_retired`;
- executing/uncleared-unknown actuator work blocks retirement;
- active tanks cannot be permanently deleted;
- retired permanent deletion preserves current cascade and media-cleanup
  behavior;
- analytics history is retained and no historical row is reassigned.

## Required web tests

- active directory defaults remain unchanged;
- administrators can open retirement confirmation and see correct consequences;
- staff cannot see the retirement action;
- retired directory/history is discoverable;
- retired detail is clearly read-only and does not show live Offline as its main
  state;
- public/control/edit actions are absent or disabled appropriately;
- permanent deletion exists only in the retired workflow with the expanded
  warning;
- mobile and narrow layouts preserve access to lifecycle filters and warnings.

## Acceptance criteria

- Taking a tank out of service no longer requires destroying its history.
- Retired tanks are excluded from live fleet, public, monitoring, ingestion,
  and equipment-control workflows.
- Historical operational data and owned media remain available to authorized
  users until deliberate permanent deletion.
- Registered devices are deactivated and cannot continue ingesting/claiming.
- Retirement is auditable, idempotent, and administrator-only.
- Permanent deletion requires prior retirement and retains existing integrity
  guarantees.
- Reactivation is not accidentally implemented.

## Non-goals

- Reactivation in the first pass.
- Multiple custom lifecycle states.
- Legal hold, configurable retention periods, bulk archival, or general asset
  management.
- Reassigning devices or historical readings.
- Automatically erasing firmware/device-resident configuration.

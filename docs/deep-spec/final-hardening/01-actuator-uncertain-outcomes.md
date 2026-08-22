# Actuator Commands With an Uncertain Physical Outcome

Classification: **Implemented P0 safety record**
Status: Implemented in current backend/web behavior
Last reviewed: 2026-08-22

## Objective

Represent the point at which AquaLogic knows that a command was claimed but can
no longer determine its physical result. Prevent software uncertainty from
causing a duplicate pump dispense.

## Verified current behavior

The current persisted lifecycle is:

```text
queued -> executing -> succeeded
                    -> failed
                    -> outcome_unknown
queued -> expired
```

The implementation already provides important safety properties:

- `ActuatorCommand.command_id` is server-generated and unique.
- Commands are bound to an authenticated registered device and its server-side
  tank mapping.
- The bridge fetches only unexpired commands for that device.
- `queued -> executing` is an atomic conditional update performed before the
  hardware request.
- Duplicate claims conflict; finalized commands cannot be claimed again.
- Matching duplicate success/failure reports are idempotent.
- The bridge makes one allowlisted physical request and does not blindly retry.
- Queued pump commands have short expiry and require a fresh device heartbeat.
- Pump dispense uses the firmware-configured volume, waits for observed
  completion, and may issue one safety stop after a bounded timeout.
- Pump controls are administrator-only, maintenance-only, and default-off in
  bridge configuration.
- Claimed commands receive a persisted 180-second confirmation deadline,
  measured from `executing_at` and independent of queue expiry.
- Shared reconciliation is called before creation, status/history reads,
  pending fetches, claim, and report operations. It conditionally finalizes
  overdue executing rows as `outcome_unknown` and records the transition audit
  once, including under concurrent workers.
- Same-device/same-pump dispense admission and claim checks are serialized;
  an uncleared unknown outcome blocks another dispense while Stop remains
  available. Administrator physical verification records actor, UTC time, and
  optional note without rewriting the historical outcome.

## Required state contract

Add a terminal persisted state with the canonical API value:

```text
outcome_unknown
```

Recommended UI label:

```text
Outcome unknown
```

Meaning:

> AquaLogic delivered or may have delivered the command to the equipment, but
> did not receive a trustworthy terminal result within the confirmation window.
> Physical execution may have occurred.

This state is terminal for bridge execution. It must never return to `queued`
or be offered as an automatic retry. A later bridge success/failure report must
not silently overwrite it; see late reports below.

### Required user-facing semantics

| State | Safe claim |
| --- | --- |
| `expired` | The request expired while queued; AquaLogic did not deliver it to equipment. |
| `succeeded` | Equipment execution/acceptance was confirmed according to the command contract. |
| `executing` | The equipment action may be underway. |
| `outcome_unknown` | Physical execution may have occurred; verify equipment before another potentially duplicative action. |
| `failed` | AquaLogic did not confirm successful completion. Failure does not universally prove that no physical action occurred. |

Do not reuse `expired` for a claimed command. Queue expiry proves non-delivery;
execution confirmation timeout does not.

## Transition rules

The approved lifecycle becomes:

```text
queued --claim--> executing --confirmed--> succeeded
                          \--reported error--> failed
                          \--confirmation deadline--> outcome_unknown
queued --queue expiry--> expired
```

Rules:

1. Only an `executing` command may transition automatically to
   `outcome_unknown`.
2. The deadline is measured from `executing_at`, not `requested_at` or
   `expires_at`.
3. Queue expiry continues to apply only while status is `queued`.
4. The transition must be persisted and audited once.
5. Repeated reconciliation must be idempotent.
6. `outcome_unknown` is excluded from the pending bridge queue.
7. No lifecycle path returns `outcome_unknown` to `queued`.
8. No automatic second hardware request is introduced.

## Confirmation-window design

Do not choose the timeout by copying the queue-expiry value. It must exceed the
longest legitimate bridge execution/report duration.

The existing bridge permits `pump_completion_timeout_seconds` from 5 to 120
seconds, defaults to 30 seconds, and also performs HTTP requests and a possible
safety stop. Therefore, the backend confirmation window must include:

```text
maximum permitted physical completion wait
+ bounded HTTP/report time
+ bridge scheduling/network margin
```

Implementation planning must define one explicit server-side setting or
constant and document its rationale. The initial value must be conservatively
greater than the bridge's maximum legitimate processing time. Hardware tests
must validate that normal commands do not age into unknown prematurely.

This pass does not require a continuously running worker solely for command
reconciliation. A small shared reconciliation service may run opportunistically
before command creation, status/history reads, and device pending/claim/report
operations. This is acceptable because same-pump creation must reconcile before
checking the safety lock. If a general scheduler is introduced, it must call the
same idempotent service rather than implement a second transition policy.

## Same-pump dispense interlock

Before creating a `dispense` command for `pump_a` or `pump_b`, the backend must:

1. resolve the authenticated target device and fixed tank as it does now;
2. reconcile stale executing commands for that device;
3. query for a prior command with the same `device_id`, same pump actuator,
   action `dispense`, and status in `executing` or `outcome_unknown`;
4. reject the new dispense with `409 Conflict` if one exists;
5. return a stable, non-secret error explaining that physical verification is
   required.

The lock scope is **same registered device + same pump actuator**. It must not
block Pump B because Pump A is uncertain. It must not use tank alone because a
tank can have multiple registered devices. It applies specifically to
`dispense`; safety `stop` must remain available. The implementation plan must
explicitly decide whether `retract` remains available during uncertainty based
on the hardware safety procedure, but it must never be treated as proof that a
dispense did not occur.

Suggested response meaning:

> Another dispense cannot be queued because an earlier command for this pump
> may have executed. Physically verify the pump before continuing.

## Administrator clearance

An unknown outcome cannot remain a permanent operational dead end. Provide a
deliberate administrator-only clearance workflow that records physical
verification without rewriting history.

Preferred minimal contract:

- keep the original command status `outcome_unknown` permanently;
- persist verification metadata on that command or in a dedicated append-only
  verification record: verifier user, verification time, and optional bounded
  note;
- treat the pump interlock as cleared only after this verification exists;
- audit the clearance event;
- never change the historical command to `succeeded` or `failed` based only on
  an operator's observation.

If adding fields to `actuator_commands`, use an Alembic migration as required by
repository rules. A simple boolean without actor/time is insufficient because
the action must remain attributable. The browser must use a confirmation dialog
that states verification clears the software lock but does not prove the exact
historical dose.

## Late bridge reports

Late reports are possible after the backend has marked a command unknown.

- A report received while still `executing` follows the existing success/fail
  path.
- A report received after `outcome_unknown` must not trigger hardware work.
- It must not silently replace the terminal unknown record.
- The backend should return a deterministic conflict or accept the report only
  as separately recorded late evidence. Whichever minimal option is chosen,
  tests and docs must state it explicitly.
- An identical repeated late report must be idempotent and must not create
  repeated audit noise.

The recommended minimal first pass is a deterministic `409` plus an audit event
that a late report was rejected. Do not add a broad reconciliation UI unless
hardware testing demonstrates that late results are routine and useful.

## Data, API, and UI impact

Likely implementation surfaces:

| Layer | Current location | Required consideration |
| --- | --- | --- |
| Persistence | `backend/app/models/device.py` | Status and verification metadata; indexes needed for the interlock query |
| Migration | `backend/alembic/versions/` | Add verification fields/indexes if selected; preserve existing rows |
| API schema | `backend/app/schemas/device.py` | Add `outcome_unknown`, history summary count, and verification projection |
| Lifecycle | `backend/app/routes/devices.py` or a new focused service | Shared reconciliation, interlock, clearance, late-report behavior, audit |
| Bridge | `bridge/esp32_bridge.py` | Preserve single execution and report behavior; no retry protocol required |
| Web models | `web/src/shared/api/models.ts` | Add status and summary/verification fields |
| Web controls/history | `web/src/features/tanks/ActuatorControlPanel.tsx` | Unknown badge, explanation, pump disable/clearance UI, status filter/count |
| Canonical docs | `docs/API_CONTRACT.md`, `docs/ARCHITECTURE.md`, Phase 05 specs | Reconcile after implementation |

The API status string should remain stable and machine-friendly. UI wording may
use spaces and sentence case.

## Concurrency requirements

The same-pump safety check must be correct under concurrent administrator
requests. A read-then-insert check without database protection may allow two
dispenses.

The implementation plan must define a transaction/locking strategy appropriate
to SQLite development and PostgreSQL target behavior. At minimum, add a focused
concurrency regression around command creation. If a portable partial unique
constraint cannot express the cleared-unknown rule cleanly, serialize pump
command creation in a small service and document the database-specific limits.
Do not weaken atomic claim behavior while adding this guard.

## Required regression tests

Backend tests in or near `backend/tests/test_actuators.py` must cover:

- executing commands below the deadline remain executing;
- commands beyond the deadline transition once to `outcome_unknown`;
- reconciliation is idempotent and emits one audit transition;
- unknown commands never appear in pending results and cannot be claimed;
- normal success/failure before the deadline still works;
- late success and failure follow the selected explicit policy;
- an executing same-device/same-pump dispense blocks another dispense;
- a reconciled unknown same-pump dispense blocks another dispense;
- verification clearance is administrator-only, attributable, and auditable;
- clearance permits a later same-pump dispense without altering old history;
- Pump A uncertainty does not block Pump B;
- another device's pump does not create a false lock;
- Stop remains available during an uncertainty lock;
- staff/public/device credentials cannot clear the lock;
- history filtering and summary counts include `outcome_unknown`;
- existing queued expiry and duplicate-report tests continue to pass.

Web tests near `ActuatorControlPanel.test.tsx` must cover:

- readable unknown status and physical-verification warning;
- unknown count/filter support;
- same-pump dispense disabled or rejected clearly without hiding Stop;
- confirmation-gated administrator clearance;
- failed, expired, executing, and succeeded wording remains distinct.

Bridge regression tests must continue proving one hardware call per claimed
command, no automatic retry, bounded pump completion monitoring, and one-shot
safety stop behavior.

## Acceptance criteria

- No command remains indefinitely represented as actively executing after its
  defined confirmation deadline.
- A claimed-but-unconfirmed command becomes a persistent, auditable unknown
  outcome rather than expired or automatically failed.
- AquaLogic never automatically duplicates the physical request.
- A second same-pump dispense is blocked while an earlier dispense is executing
  or unknown and uncleared.
- A named administrator can record physical verification and clear the lock
  without rewriting the original outcome.
- UI and API wording do not claim that failure or silence proves non-execution.
- Existing claim, expiry, authorization, fixed mapping, and idempotency
  guarantees remain intact.

## Non-goals

- Automatic command retry or replay.
- Automatic chemical dosing or sensor-driven pump behavior.
- A generalized workflow engine, distributed job platform, or fleet failover.
- Inferring physical truth from a missing network acknowledgement.
- Retrofitting unknown status onto already finalized historical commands.

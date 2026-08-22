# Final Hardening Implementation Order and Consistency Audit

Classification: **Execution and verification guide**  
Status: Approved order  
Last reviewed: 2026-08-22

## Planning standard

Before each work packet, the implementation agent must:

1. read `AGENTS.md`, `docs/INDEX.md`, `docs/DEVELOPMENT_STATUS.md`, and relevant
   area/phase docs;
2. inspect current source and tests named by the packet;
3. check `git status --short` and preserve unrelated changes;
4. produce a file-level plan including migration, API, UI, tests, docs, risks,
   and rollback/compatibility where relevant;
5. run the smallest tests while iterating, then the complete validation for each
   affected application.

Do not combine all work into one undifferentiated patch. The order below is
chosen so the highest physical risk is resolved first and product-gated work
cannot accidentally enter the base scope.

## Recommended implementation order

### 1. Actuator uncertain-outcome safety

Implement packet 01 as a focused backend/API/web/migration slice. Preserve
bridge no-retry behavior. Validate with backend and web regression plus bridge
tests and the existing hardware runbook. This is the release-blocking technical
item.

Suggested internal sequence:

1. lock the lifecycle/timeout/clearance contract in an implementation plan;
2. add migration/model/schema changes;
3. add idempotent reconciliation and same-pump interlock;
4. add clearance and late-report policy;
5. update history/status APIs and web models;
6. add UI warning/filter/clearance behavior;
7. run concurrency, lifecycle, bridge, and hardware checks;
8. reconcile Phase 05, API, architecture, and development-status docs.

### 2. Offline and last-known clarity

Add shared reporting-age presentation and stale/offline-aware labels. Extend the
authenticated operations contract only if needed to avoid using observation
time as freshness evidence.

### 3. Manual alert terminology

Change operator-facing wording to Mark handled and add the non-recovery
explanation. Preserve the existing backend route/storage unless a concrete
contract need appears.

### 4. Operational status versus Species Care explanation

Add concise explanatory text and a regression case where the two results
differ legitimately.

### 5. Species Care scope wording

Make the water-only scope and lack of pairwise compatibility explicit. Align
chips, filters, summaries, and accessibility text.

### 6. Threshold boundary helper text

Explain strict/open boundaries. Do not touch the evaluator or historical data.

### 7. Tank deletion warning

Update both deletion surfaces and tests with the verified cascade consequences.

### 8. Tank local-media cleanup

Add safe database-first cleanup and filesystem edge-case coverage.

### 9. Device move/reprovisioning documentation

Publish the operator workflow and cross-link Phase 01/device docs.

### 10. Hardware deletion/decommissioning guidance

Publish the pre-delete equipment/schedule cleanup procedure and clearly state
the database/physical boundary.

### 11. Implement retired-tank lifecycle

Packet 08 is implemented as a separate migration, backend, web, and
documentation slice. Retirement retains history, removes a tank from live
operations, disables its public/control/monitoring expectations, and precedes
any permanent deletion. Reactivation remains out of scope; packet 09's
incident model and worker are integrated.

### 12. Implemented persistent unattended monitoring incidents

Packet 09 is implemented after the tank lifecycle contract, so incident
eligibility and retirement resolution use one definition of an active tank.
Incidents remain tank-level and in-app only. External notifications are not
included.

### 13. Leave fish compatibility unchanged

Do not add compatibility evaluation, structured pairwise rules, assignment
blocking, or new result statuses. Revisit only after a later explicit decision.

### 14. Final SRS/deep-spec/implementation consistency audit

Run the audit below after approved behavior is implemented.

### 15. Regression validation

Run full affected suites and record exact results in
`docs/DEVELOPMENT_STATUS.md`.

### 16. UI/shadcn refinement pass

Perform a final responsive, accessible visual polish only after semantics and
tests are stable. Do not use this step to introduce new workflows.

## Required validation matrix

| Change | Minimum focused validation | Completion validation |
| --- | --- | --- |
| Actuator lifecycle | `backend/tests/test_actuators.py`, web actuator tests, bridge tests | Full backend pytest, web typecheck/test/build, hardware runbook evidence |
| Monitoring/alert/species copy | Relevant fleet, tank, alert, threshold tests | Full web typecheck/test/build; backend contract test if API changes |
| Tank deletion/media | Tank media, integrity, permissions tests | Full backend pytest and web deletion component tests |
| Retired tank lifecycle | New lifecycle route/service, list visibility, write guards, public/privacy and device tests | Full backend pytest, Alembic upgrade, web typecheck/test/build |
| Monitoring incidents | Detection/recovery service, worker idempotency, eligibility and API tests | Full backend pytest, worker/restart validation, web typecheck/test/build |
| Documentation-only workflows | Link/path review and source verification | Documentation consistency audit |
| Owner-approved schema/API work | New focused tests and migration on fresh/existing DB | Full affected apps plus Alembic upgrade validation |

Use the commands in root `AGENTS.md`. Hardware tests must use empty syringes or
water only and follow the existing runbook.

## Final consistency audit

Compare:

```text
current implementation
<-> docs/deep-spec
<-> canonical architecture/domain/API/workflow docs
<-> SRS and older proposals
<-> actual UI terminology
```

Verify each item below with code/tests as authority:

- exactly four currently supported live monitoring parameters: temperature,
  pH, turbidity, and TDS;
- Species Care's supported set: temperature, pH, and TDS;
- temporary private-LAN ESP32 bridge architecture and fixed device credentials;
- 90-second server-receipt freshness and Offline behavior;
- last-known versus current presentation;
- alert record versus notification-delivery terminology;
- operator handled versus system-confirmed resolution;
- strict/open operational threshold boundary semantics;
- advisory, water-only Species Care meaning;
- notes-only compatibility scope unless a later explicit decision replaces it;
- device movement as new provisioning;
- device-resident schedule and database-deletion boundary;
- guarded/manual pump maintenance, not chemical dosing;
- command outcome-unknown behavior and same-pump interlock;
- active versus retired tank behavior and retained history;
- 90-second request-time Offline versus 15-minute persistent outage behavior.

For every inconsistency:

1. confirm current behavior from source/tests;
2. update current canonical/deep-spec documentation;
3. label unimplemented material Planned, Decision required, Deferred, or
   Historical;
4. do not keep an outdated claim merely because it exists in an older proposal.

## Documentation closure checklist

- Update `docs/DEVELOPMENT_STATUS.md` with completed behavior and validation.
- Add dated important choices to `docs/DECISIONS.md`.
- Update `docs/API_CONTRACT.md` for status enums/fields/routes/copy semantics.
- Update `docs/ARCHITECTURE.md` for lifecycle or worker changes.
- Update affected Phase 01–06 files from approved behavior to implemented
  behavior.
- Update area guides if important source locations or conventions change.
- Keep this package as the review/handoff record; do not make it the only place
  that documents final current behavior.

## Exit criteria

- All P0/P1 acceptance criteria pass.
- No undecided fish-compatibility branch appears in shipped behavior.
- Deferred items remain explicitly deferred.
- Full validations pass or an existing unrelated failure is documented with
  evidence.
- Hardware-dependent claims are supported by hardware test evidence.
- UI, API, tests, and current documentation use compatible terminology.

## Luna Extra High goal prompt

```text
You are working in the current AquaLogic repository. Execute the final hardening
consistency and release-readiness audit described in:
docs/deep-spec/final-hardening/07-implementation-order-and-consistency-audit.md

Use this prompt only after the intended implementation goals are complete. Read
AGENTS.md, docs/INDEX.md, docs/DEVELOPMENT_STATUS.md, docs/DECISIONS.md, the
final-hardening hub and every numbered packet, relevant canonical/area/phase
docs, current source/tests, and git status.

First inventory which goals are implemented, partially implemented, planned, or
still deferred. Do not assume a document marked approved means its code exists.
Build an evidence-backed audit matrix covering implementation, migration/API,
UI terminology, focused tests, full validation, documentation reconciliation,
and hardware evidence for each applicable goal.

Inspect and correct inconsistencies across current implementation, deep specs,
canonical architecture/domain/API/workflow docs, SRS/older proposals, and UI.
Source and tests are authoritative for current behavior. Label unimplemented
material Planned, Decision required, Deferred, or Historical. Leave fish
compatibility notes-only. Do not introduce new product behavior during this
audit; any real implementation gap must be reported and returned to its bounded
goal unless the user explicitly authorizes the fix.

Run the complete validation matrix for affected applications: backend tests,
Alembic upgrade on fresh and representative existing databases, bridge tests,
web typecheck/tests/build, and recorded safe hardware validation where required.
Perform responsive/accessibility refinement only when it does not change
workflow scope. Update DEVELOPMENT_STATUS with exact evidence and affected
canonical/phase documentation with final implemented semantics.

Finish with: goal status table, inconsistencies corrected, validations and exact
results, remaining hardware/manual checks, deferred items confirmed, and a clear
release-readiness conclusion.
```

# JRed Aquatics Client Validation Decisions

Classification: **Product-decision record**  
Status: Tank history and unattended monitoring owner-approved; fish compatibility undecided  
Last reviewed: 2026-08-22

## Purpose

Record the three product questions that materially affect the final hardening
scope. On 2026-08-21, the project owner authorized AquaLogic to choose bounded
defaults for tank history and unattended monitoring. Those two choices were
owner-approved bounded work. They are not represented as direct statements from a
JRed representative.

Fish compatibility remains deliberately undecided. Current notes-only behavior
must remain unchanged until the owner provides a later direction.

## Decision A — retired tank history

Decision status: **Owner approved — implemented in packet 08**

### Ask exactly

> When a physical tank is no longer used, do you still need AquaLogic to retain
> and show its historical water readings, alerts, and equipment history?

### Current behavior

Permanent tank deletion cascades tank-owned readings, alerts, commands/state
history, device registrations, species assignments, configuration, and public
page data. Security audit records survive by plain target identifier. There is
no undelete.

### Approved direction

Implement a small tank lifecycle:

```text
active -> retired
```

Minimum expected behavior for the later implementation plan:

- retired tanks leave normal live fleet and control workflows;
- historical readings, alerts, assignments, and equipment history remain
  readable to authorized users;
- devices are deactivated and controls are unavailable before/at retirement;
- public pages are disabled or explicitly reviewed;
- list APIs and UI filters distinguish active from retired;
- permanent deletion, if retained, remains a separate administrator action with
  a stronger confirmation;
- schema changes use Alembic and existing active rows are backfilled safely.

Reactivation is not included in the first pass. The detailed contract is in
[`08-retired-tank-lifecycle.md`](08-retired-tank-lifecycle.md).

### Still out of scope after yes

- General asset-management workflows.
- Arbitrary retention policies and legal hold.
- Versioned restoration of every tank configuration.

## Decision B — fish-to-fish compatibility

Decision status: **Undecided — leave current behavior unchanged**

### Ask exactly

> Do you want AquaLogic to help staff determine whether different fish species
> can share one tank, or is that already handled through staff knowledge and
> existing practices?

### Current behavior

Species Care compares each assigned species independently against fresh
temperature, pH, and TDS values. Compatibility notes are unstructured staff
guidance. Assignment does not calculate pairwise coexistence or block staff.

### Current instruction

Do not select either branch yet. Keep the current model and implement only the
already-approved water-only Species Care scope wording. Compatibility remains
free-text guidance and must not affect assignments or suitability.

### Possible later direction, not approved

Do not build a general biological engine. First collect the small set of species
JRed actually handles and the guidance JRed trusts. Plan a curated, explainable
system with a bounded result such as:

```text
compatible
compatible_with_caution
not_recommended
insufficient_information
```

Every result must include a human-readable reason. Only reliably maintained
factors may be structured, for example water-range overlap, temperament,
territorial behavior, size/predation risk, group requirements, or tank space.
The implementation plan must define ownership and update workflow for the
curated data before writing an evaluator.

### Still out of scope after yes

- AI-generated care decisions.
- Universal species coverage.
- Breeding, spawning, fry, or pregnancy management.
- Automatic assignment without staff confirmation.

## Decision C — unattended monitoring outages

Decision status: **Owner approved — implement after P0/P1 hardening**

### Ask exactly

> If a monitoring device stops sending readings while nobody is viewing
> AquaLogic, such as overnight, do you need AquaLogic to automatically record
> that outage for staff to review later?

### Current behavior

The dashboard derives Offline after 90 seconds without a fresh accepted reading
when status is requested. There is no background freshness worker or persistent
offline incident. Analytics later reconstructs reporting gaps from receipt-time
intervals. There is no push, email, SMS, or browser notification subsystem.

### Approved direction

Implement a lightweight persistent in-app monitoring incident after a
configurable 15-minute grace period, separate from the 90-second live-dashboard
freshness threshold:

```text
no fresh reading for 90 seconds
-> live dashboard shows Offline

no fresh reading for configured outage grace period
-> background check creates/updates one persistent monitoring incident
```

The approved design uses one incident per tank rather than per device. The
detailed contract is in
[`09-persistent-monitoring-incidents.md`](09-persistent-monitoring-incidents.md).
It defines:

- one active outage incident per eligible tank;
- opening time, last-seen context, recovery time, and recovery semantics;
- restart/idempotency behavior for the scheduled check;
- handling of deactivated devices and tanks without provisioned devices;
- visibility in the existing in-app operational workflow;
- a deployment-appropriate lightweight scheduler/worker ownership model.

The 90-second status rule should not automatically become the persistent
incident grace period; transient network loss would create noise.

### Still out of scope after yes

- Push, email, SMS, or provider delivery infrastructure.
- Enterprise monitoring/observability stacks.
- On-call routing and escalation management.

## Future compatibility decision record template

```text
Date:
JRed representative:
Question: Fish compatibility
Answer: Yes | No
Reason / workflow detail:
Approved bounded follow-up:
Explicitly excluded:
```

## Completion rule

Packets 08 and 09 are implemented owner-approved work. Fish compatibility is
not. Silence or lack of a later direction is not approval for compatibility
functionality.

## Luna Extra High goal prompt

```text
You are working in the current AquaLogic repository. Audit product-decision
compliance using:
docs/deep-spec/final-hardening/05-client-validation-decisions.md

This is a decision/guardrail goal, not authorization to implement all branches.
Read AGENTS.md, docs/INDEX.md, docs/DECISIONS.md, docs/DEVELOPMENT_STATUS.md, the
final-hardening hub, packets 08 and 09, and current Species Care/compatibility
specs. Inspect current source, tests, documentation, and git status.

Confirm and report that:
- retired tank history is implemented owner-approved work governed by packet 08;
- persistent tank-level monitoring incidents are owner-approved implemented
  work governed by packet 09;
- fish-to-fish compatibility remains undecided and notes-only;
- none of these owner decisions is falsely attributed to a JRed representative;
- adjacent external notifications, generalized asset management, and biological
  compatibility-engine scope remain unapproved.

If the user explicitly asks for a plan for packet 08 or 09, produce a bounded
file-level plan for that packet only. Otherwise make documentation corrections
only. Do not add pairwise scores, compatibility statuses, assignment blocking,
structured compatibility data, or an AI care engine. Finish with a short
decision-compliance report and any contradictions found.
```

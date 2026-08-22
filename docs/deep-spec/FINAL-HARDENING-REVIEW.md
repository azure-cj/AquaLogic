# Final AquaLogic Hardening Review

Status: Authoritative implementation record and scope guardrail; Goals 1–5 implemented
Last reviewed: 2026-08-22

## Purpose

This package converts the final external panel-style stress review into bounded,
implementation records and scope guardrails for AquaLogic. It is the
authoritative record for the last hardening pass after Phases 01–06.

This is not a seventh feature phase. The governing principle is:

> Depth over breadth. Fix real weaknesses. Do not introduce unnecessary scope.

The supporting specifications contain enough verified repository context,
behavioral rules, likely change surfaces, edge cases, tests, and acceptance
criteria for an implementation agent to produce a detailed plan without the
original review transcript.

## How to use this package

1. Read this file and the work packet for the behavior being changed or audited.
2. Reinspect every named source and test before editing; line numbers may move.
3. Preserve the invariants and non-goals in the work packet.
4. Treat implemented packets as the current behavior record, not as permission
   to broaden scope.
5. Leave the undecided fish-compatibility branch unchanged.
6. Treat **Deferred** items as scope boundaries, not as a backlog.
7. Update the relevant Phase 01–06 deep spec after implementation so current
   behavior is not documented only in this review package.

## Review result

The implemented architecture remained coherent under review. Monitoring
freshness, alert deduplication, system/operator resolution metadata, global
threshold separation, fixed device-to-tank ownership, and the physical-command
claim/no-retry fundamentals should be preserved.

Goal 1's high-priority physical-safety gap, Goal 2's tank-deletion cleanup,
warning, and device-movement documentation, Goal 3's monitoring and Species
Care terminology hardening, Goal 4's retained tank lifecycle, and Goal 5's
persistent monitoring-incident model/worker are implemented. Remaining work is
bounded to physical/deployment validation for claims software cannot prove and
the unresolved fish-compatibility decision; no implementation is authorized by
that unresolved decision.

## Work packet index

| Packet | Classification | Outcome |
| --- | --- | --- |
| [`01-actuator-uncertain-outcomes.md`](final-hardening/01-actuator-uncertain-outcomes.md) | **Implemented P0 safety record** | Persist uncertain physical outcomes and prevent duplicative pump dispense |
| [`02-tank-deletion-and-decommissioning.md`](final-hardening/02-tank-deletion-and-decommissioning.md) | **Implemented** | Clean owned media, warn accurately, and document hardware cleanup |
| [`03-ui-terminology-and-clarity.md`](final-hardening/03-ui-terminology-and-clarity.md) | **Implemented** | Make freshness, alert, Species Care, and threshold meaning unambiguous |
| [`04-device-movement-and-provisioning.md`](final-hardening/04-device-movement-and-provisioning.md) | **Implemented** | Define a safe move-as-reprovisioning workflow |
| [`05-client-validation-decisions.md`](final-hardening/05-client-validation-decisions.md) | **Decision record — fish compatibility undecided** | Record settled owner decisions and the remaining bounded product question |
| [`06-deferred-scope-and-preserved-design.md`](final-hardening/06-deferred-scope-and-preserved-design.md) | **Scope guardrail** | Prevent feature creep and unnecessary redesign |
| [`07-implementation-order-and-consistency-audit.md`](final-hardening/07-implementation-order-and-consistency-audit.md) | **Completed audit record** | Preserve implementation order, validation expectations, and final reconciliation evidence |
| [`08-retired-tank-lifecycle.md`](final-hardening/08-retired-tank-lifecycle.md) | **Implemented** | Retain retired-tank history outside active operations |
| [`09-persistent-monitoring-incidents.md`](final-hardening/09-persistent-monitoring-incidents.md) | **Implemented** | Persist unattended tank-level reporting outages in-app |

## Priority summary

### P0 — physical safety and correctness

Goal 1 adds the persistent terminal state `outcome_unknown` for a command
that was claimed and may have physically executed but can no longer be
confirmed. A same-device, same-pump `dispense` is blocked while an earlier
dispense is `executing` or uncleared `outcome_unknown`. The implementation does
not retry, silently fail, or infer that missing confirmation means no action
occurred. Hardware timing and safe physical verification remain to be validated.

### P1 — operational clarity and cleanup

- Label stale/offline values as last-known context and use
  `reporting_age_seconds` where available. **Implemented in Goal 3.**
- Rename the operator alert action from Resolve to Mark handled in the UI while
  preserving backend lifecycle semantics. **Implemented in Goal 3.**
- Explain the difference between global operational status and advisory Species
  Care, and state the water-only scope of Species Care. **Implemented in Goal 3.**
- Explain strict/open threshold boundary semantics without changing the
  algorithm. **Implemented in Goal 3.**
- Expand permanent tank-deletion warnings and remove tank-owned local hero media
  only after a successful database deletion. **Implemented in Goal 2.**
- Document device-resident cleanup and the device move/reprovisioning workflow.
  **Implemented in Goal 2.**

### P2 — approved bounded additions

The project owner approved two previously client-gated additions on 2026-08-21:

- a retained `Active -> Retired` tank lifecycle, specified in packet 08;
- persistent tank-level unattended monitoring incidents after a configurable
  15-minute grace period, specified in packet 09.

The retained tank lifecycle and persistent monitoring incidents are now current
behavior. Fish-to-fish compatibility remains undecided and must stay
notes-only until the project owner supplies a later direction.

## Product-decision status

| Question | Status | Direction |
| --- | --- | --- |
| Tank history | **Owner approved** | Add retirement and retain historical data |
| Fish compatibility | **Still undecided** | Leave the current notes-only behavior unchanged |
| Unattended monitoring | **Owner approved** | Add persistent, in-app, tank-level outage incidents |

The owner decisions are internal product direction and must not be described as
quotes or approval from a named JRed representative.

## Definition of completion

The final hardening pass is complete only when:

- all approved P0/P1 behavior is implemented and regression-tested;
- owner-approved product decisions are implemented and recorded, while fish
  compatibility remains unchanged until separately decided;
- affected Phase 01–06 specs, canonical docs, API wording, and UI terminology
  agree with the code;
- the final audit in packet 07 passes;
- backend and web validation pass, plus bridge tests when actuator behavior is
  touched;
- actual hardware validation is recorded for physical-command timing and safety
  claims that software tests cannot prove.

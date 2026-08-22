# Final AquaLogic Hardening Review

Status: Authoritative implementation roadmap; Goals 1–5 implemented  
Last reviewed: 2026-08-22

## Purpose

This package converts the final external panel-style stress review into bounded,
implementation-ready work for AquaLogic. It is the authoritative planning
source for the last hardening pass after Phases 01–06.

This is not a seventh feature phase. The governing principle is:

> Depth over breadth. Fix real weaknesses. Do not introduce unnecessary scope.

The supporting specifications contain enough verified repository context,
behavioral rules, likely change surfaces, edge cases, tests, and acceptance
criteria for an implementation agent to produce a detailed plan without the
original review transcript.

## How to use this package

1. Read this file and the work packet for the item being planned.
2. Reinspect every named source and test before editing; line numbers may move.
3. Preserve the invariants and non-goals in the work packet.
4. Implement only items marked **Fix now** or **Polish now**.
5. Implement owner-approved packets 08 and 09 only in their scheduled order;
   leave the undecided fish-compatibility branch unchanged.
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
Care terminology hardening, and Goal 4's retained tank lifecycle are
implemented. The remaining work is bounded to the separate client decisions
and packet 09's persistent monitoring-incident model/worker are implemented.

## Work packet index

| Packet | Classification | Outcome |
| --- | --- | --- |
| [`01-actuator-uncertain-outcomes.md`](final-hardening/01-actuator-uncertain-outcomes.md) | **Fix now — P0** | Persist uncertain physical outcomes and prevent duplicative pump dispense |
| [`02-tank-deletion-and-decommissioning.md`](final-hardening/02-tank-deletion-and-decommissioning.md) | **Implemented** | Clean owned media, warn accurately, and document hardware cleanup |
| [`03-ui-terminology-and-clarity.md`](final-hardening/03-ui-terminology-and-clarity.md) | **Implemented** | Make freshness, alert, Species Care, and threshold meaning unambiguous |
| [`04-device-movement-and-provisioning.md`](final-hardening/04-device-movement-and-provisioning.md) | **Implemented** | Define a safe move-as-reprovisioning workflow |
| [`05-client-validation-decisions.md`](final-hardening/05-client-validation-decisions.md) | **Client decision required** | Record the only three open product questions and their bounded branches |
| [`06-deferred-scope-and-preserved-design.md`](final-hardening/06-deferred-scope-and-preserved-design.md) | **Preserve/defer** | Prevent feature creep and unnecessary redesign |
| [`07-implementation-order-and-consistency-audit.md`](final-hardening/07-implementation-order-and-consistency-audit.md) | **Execution guide** | Sequence implementation, validation, and final reconciliation |
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

## Luna Extra High coordination prompt

Use this prompt to begin or resume the overall hardening program. Do not use it
to authorize all implementation in one task.

```text
You are working in the current AquaLogic repository. The actual Git repository
is the nested AquaLogic/ directory.

Coordinate the final hardening program described by:
- docs/deep-spec/FINAL-HARDENING-REVIEW.md
- docs/deep-spec/final-hardening/07-implementation-order-and-consistency-audit.md

Read the repository AGENTS.md, docs/INDEX.md, docs/DEVELOPMENT_STATUS.md, and the
relevant area/phase documentation before proposing work. Inspect current source,
tests, and git status; preserve unrelated changes.

Do not implement the whole hardening program as one monolithic change. Determine
the first incomplete goal in the approved order, read that goal's full work
packet and embedded Luna Extra High prompt, and produce a file-level
implementation plan for that goal only. Identify persistence/API/UI/test/docs
impact, dependencies, risks, validation commands, and explicit non-goals.

After the plan is approved or if the task explicitly authorizes implementation,
complete only that bounded goal, validate it in proportion to risk, update all
affected canonical and phase documentation, and report acceptance-criteria
coverage. Do not implement fish-to-fish compatibility. Do not convert deferred
items into backlog work. Never weaken fixed device/tank ownership, strict
threshold semantics, freshness behavior, alert deduplication, or physical-command
no-retry safety.
```

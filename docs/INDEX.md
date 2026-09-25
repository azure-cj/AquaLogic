# AquaLogic Documentation Index

Last reviewed: 2026-09-25

This is the documentation entry point for people and coding agents. Read the
root `AGENTS.md` first when changing the repository, then use this index to
choose only the context relevant to the task.

## Canonical current documentation

These files are the stable source of truth for the current implementation. The
area guides and deep specs provide navigation and feature detail; they should
link back here rather than duplicate a competing project status.

| Document | Use it for |
| --- | --- |
| [`PROJECT_CONTEXT.md`](PROJECT_CONTEXT.md) | Product purpose, users, scope, constraints, and terminology |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Implemented components, data flow, boundaries, and extension points |
| [`DOMAIN_MODEL.md`](DOMAIN_MODEL.md) | Domain entities, relationships, statuses, and invariants |
| [`API_CONTRACT.md`](API_CONTRACT.md) | Current backend routes, authentication, public access, and client expectations |
| [`GIT_WORKFLOW.md`](GIT_WORKFLOW.md) | Branching, commits, pull requests, and hardware/software collaboration |
| [`DEVELOPMENT_STATUS.md`](DEVELOPMENT_STATUS.md) | What is complete, active, planned, deferred, and known to be limited |
| [`DECISIONS.md`](DECISIONS.md) | Important decisions and their reasons |
| [`WORKFLOWS.md`](WORKFLOWS.md) | Local setup, validation, database, browser, and deployment workflows |

## Operational documentation

- [`operations/hardware/`](operations/hardware/): the hardware contract, bridge
  integration notes, and safe local hardware-test runbook.

## Area guides

- [`areas/BACKEND.md`](areas/BACKEND.md): FastAPI, database, migrations, tests,
  and sensor/alert behavior.
- [`areas/WEB.md`](areas/WEB.md): React structure, routes, API usage, and UI
  validation.
- [`areas/MOBILE.md`](areas/MOBILE.md): Flutter prototype structure and current
  demo-data boundary.
- [`areas/FIRMWARE.md`](areas/FIRMWARE.md): ESP32 sketch, bundled libraries,
  hardware scope, and future integration boundary.

## Current implementation deep specs

- [`deep-spec/FINAL-HARDENING-REVIEW.md`](deep-spec/FINAL-HARDENING-REVIEW.md):
  implementation record and scope guardrail for the final cross-cutting safety,
  correctness, clarity, and client-validation pass after Phases 01–06. Goals 1–5
  are implemented; persistent monitoring incidents are current behavior under
  packet 09.

- [`deep-spec/phase-06-access-and-platform/`](deep-spec/phase-06-access-and-platform/):
  current behavior and hardening record for authentication, account security,
  staff lifecycle, authorization, integrity, and local recovery.
- [`deep-spec/phase-01-domain-foundation/`](deep-spec/phase-01-domain-foundation/):
  current domain behavior and approved hardening scope for tanks, devices,
  bridge ingestion, sensor readings, and fish species.
- [`deep-spec/phase-02-monitoring-engine/`](deep-spec/phase-02-monitoring-engine/):
  current threshold, reading-validation boundary, freshness, status, alert
  lifecycle, and in-app notification behavior.
- [`deep-spec/phase-03-species-care/`](deep-spec/phase-03-species-care/):
  current species profiles, advisory water suitability, notes-only compatibility,
  and tank species assignments, including the implemented public projection and
  deferred compatibility scope.
- [`deep-spec/phase-04-operations/`](deep-spec/phase-04-operations/):
  fleet overview, tank workspace, alert history, operational analytics, and
  privacy-safe public tank pages, including the approved receipt-time analytics
  hardening target.
- [`deep-spec/phase-05-equipment-control/`](deep-spec/phase-05-equipment-control/):
  registered equipment connections, UV/LED/feeder controls, device-resident
  schedules, guarded pump maintenance, command lifecycle, and actuator audit
  history.

## Historical plans and reports

These documents are preserved because they contain useful history or proposal
material. They are not the primary source of current implementation behavior.

They are intentionally kept separate from current status in this index.

- [`history/reports/WEB_DASHBOARD_IMPLEMENTATION_REPORT.md`](history/reports/WEB_DASHBOARD_IMPLEMENTATION_REPORT.md)
  is a historical implementation checkpoint for the web dashboard. It is
  retained for history; current route, validation, and release status come from
  `DEVELOPMENT_STATUS.md`, canonical docs, and source/tests.
- [`history/proposals/AQUALOGIC_CONTEXT.md`](history/proposals/AQUALOGIC_CONTEXT.md) is the original business and
  academic proposal context.
- [`history/proposals/AquaLogic_Full_Software_Development_Plan.md`](history/proposals/AquaLogic_Full_Software_Development_Plan.md)
  is an earlier full-stack plan with some superseded directory and stack
  assumptions.
- [`history/proposals/AquaLogic_Implementation_Plan.md`](history/proposals/AquaLogic_Implementation_Plan.md) is an
  earlier execution plan; use it for intent and milestones, not current status.
- [`history/proposals/MOBILE_APP_DEVELOPMENT_PLAN.md`](history/proposals/MOBILE_APP_DEVELOPMENT_PLAN.md) contains
  early mobile and hardware ideas. The current app is Flutter, and the source
  code is authoritative.

## Documentation rules

- Put stable project knowledge in the canonical documents above, not in a task
  transcript.
- Add a `Last reviewed` date when materially changing a document.
- Prefer links to source files and tests over copying large code blocks.
- Clearly label information as `Current`, `Planned`, `Deferred`, or `Historical`.
- When an old plan becomes misleading, update this index and either reconcile it
  or move it to `history/`.

## Source-of-truth map

| Question | Authoritative location |
| --- | --- |
| What is implemented, deferred, or still pending? | [`DEVELOPMENT_STATUS.md`](DEVELOPMENT_STATUS.md) |
| What are the system boundaries and data flows? | [`ARCHITECTURE.md`](ARCHITECTURE.md) |
| What entities, states, and invariants exist? | [`DOMAIN_MODEL.md`](DOMAIN_MODEL.md) |
| What routes and response contracts exist? | [`API_CONTRACT.md`](API_CONTRACT.md) |
| Why was a cross-cutting choice made? | [`DECISIONS.md`](DECISIONS.md) |
| How is a local or operational task performed? | [`WORKFLOWS.md`](WORKFLOWS.md) and the hardware runbooks |
| How does a feature behave in detail? | The relevant `deep-spec/` phase or hardening packet |
| What was proposed or previously reported? | The historical documents listed above |

## Evidence

Browser screenshots and other validation artifacts are evidence, not current
behavioral specifications. See [`evidence/`](evidence/) and interpret artifacts
with the validation notes in `DEVELOPMENT_STATUS.md`.

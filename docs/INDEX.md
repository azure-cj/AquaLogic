# AquaLogic Documentation Index

Last reviewed: 2026-07-27

This is the documentation entry point for people and coding agents. Read the
root `AGENTS.md` first when changing the repository, then use this index to
choose only the context relevant to the task.

## Canonical current documentation

| Document | Use it for |
| --- | --- |
| [`PROJECT_CONTEXT.md`](PROJECT_CONTEXT.md) | Product purpose, users, scope, constraints, and terminology |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Implemented components, data flow, boundaries, and extension points |
| [`DOMAIN_MODEL.md`](DOMAIN_MODEL.md) | Domain entities, relationships, statuses, and invariants |
| [`API_CONTRACT.md`](API_CONTRACT.md) | Current backend routes, authentication, public access, and client expectations |
| [`HARDWARE_INTEGRATION_CONTRACT.md`](HARDWARE_INTEGRATION_CONTRACT.md) | Draft device payload, units, failure behavior, and actuator boundary |
| [`ESP32_BRIDGE_INTEGRATION_PLAN.md`](ESP32_BRIDGE_INTEGRATION_PLAN.md) | Implemented no-firmware-change bridge test for the received ESP32 code |
| [`ESP32_BRIDGE_HARDWARE_TEST_RUNBOOK.md`](ESP32_BRIDGE_HARDWARE_TEST_RUNBOOK.md) | Temporary owner/tester procedure for the implemented bridge test |
| [`GIT_WORKFLOW.md`](GIT_WORKFLOW.md) | Branching, commits, pull requests, and hardware/software collaboration |
| [`DEVELOPMENT_STATUS.md`](DEVELOPMENT_STATUS.md) | What is complete, active, planned, deferred, and known to be limited |
| [`DECISIONS.md`](DECISIONS.md) | Important decisions and their reasons |
| [`WORKFLOWS.md`](WORKFLOWS.md) | Local setup, validation, database, browser, and deployment workflows |

## Area guides

- [`areas/BACKEND.md`](areas/BACKEND.md): FastAPI, database, migrations, tests,
  and sensor/alert behavior.
- [`areas/WEB.md`](areas/WEB.md): React structure, routes, API usage, and UI
  validation.
- [`areas/MOBILE.md`](areas/MOBILE.md): Flutter prototype structure and current
  demo-data boundary.
- [`areas/FIRMWARE.md`](areas/FIRMWARE.md): ESP32 sketch, bundled libraries,
  hardware scope, and future integration boundary.

## Existing plans and reports

These documents are preserved because they contain useful history or proposal
material. They are not the primary source of current implementation behavior.

- [`WEB_DASHBOARD_IMPLEMENTATION_REPORT.md`](WEB_DASHBOARD_IMPLEMENTATION_REPORT.md)
  is the latest implementation report for the web dashboard and should be read
  alongside `DEVELOPMENT_STATUS.md`.
- [`AQUALOGIC_CONTEXT.md`](AQUALOGIC_CONTEXT.md) is the original business and
  academic proposal context.
- [`AquaLogic_Full_Software_Development_Plan.md`](AquaLogic_Full_Software_Development_Plan.md)
  is an earlier full-stack plan with some superseded directory and stack
  assumptions.
- [`AquaLogic_Implementation_Plan.md`](AquaLogic_Implementation_Plan.md) is an
  earlier execution plan; use it for intent and milestones, not current status.
- [`MOBILE_APP_DEVELOPMENT_PLAN.md`](MOBILE_APP_DEVELOPMENT_PLAN.md) contains
  early mobile and hardware ideas. The current app is Flutter, and the source
  code is authoritative.

## Documentation rules

- Put stable project knowledge in the canonical documents above, not in a task
  transcript.
- Add a `Last reviewed` date when materially changing a document.
- Prefer links to source files and tests over copying large code blocks.
- Clearly label information as `Current`, `Planned`, `Deferred`, or `Historical`.
- When an old plan becomes misleading, update this index and either reconcile it
  or move it to an archive in a separate cleanup task.

# AquaLogic Architecture Decisions

Status: Living decision log
Last reviewed: 2026-07-27

Record choices that affect multiple components or future work. Small local
implementation choices belong in code and tests; do not turn this into a diary.

## 2026-07-27 — Use layered project context

**Decision:** Keep `AGENTS.md` as a short operating guide and use focused
canonical documents under `docs/` for product context, architecture, contracts,
status, and workflows.

**Reason:** A single large context file becomes difficult to keep current and
causes agents to load irrelevant history. The index lets an agent select the
smallest useful context set.

## 2026-07-27 — Treat the nested `AquaLogic` directory as the repository root

**Decision:** Place agent instructions and canonical documentation in the
nested directory that contains `.git`, `backend`, `web`, `mobile_app`, and
`docs`.

**Reason:** That is the actual Git root and is the stable boundary for source,
tests, and documentation. The parent folder is only a workspace container.

## 2026-07-27 — Keep software-first, local-first development

**Decision:** Develop and validate backend, web, mobile prototype, and seeded
data before making hardware integration a prerequisite.

**Reason:** The system can demonstrate operational value and stabilize its data
contract before sensors and actuators are available.

## 2026-07-27 — Use the current source as the implementation authority

**Decision:** The route modules, schemas, models, migrations, tests, and current
web/mobile source override earlier plans when they disagree.

**Reason:** The repository has accumulated proposal documents and implementation
reports from different phases. The documentation index labels those documents
without deleting useful historical context.

## Adding a decision

Use this format:

```md
## YYYY-MM-DD — Short decision title

**Decision:** What will be done.

**Reason:** Why this choice was made.

**Consequences:** What this makes easier, harder, or deferred.
```

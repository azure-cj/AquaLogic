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

## 2026-07-27 â€” Make admin navigation adaptive from one grouped config

**Decision:** Define Monitor, Manage, and Configure navigation groups once and
render their items flat until more than eight configured pages exist. At
desktop widths below 1200px, or above that page limit, render the same groups
as click-toggle dropdowns; retain the mobile drawer below 820px.

**Reason:** The navigation can grow without duplicating route definitions or
adding width measurement logic, while preserving the current wide-screen
experience.

**Consequences:** Adding a ninth configured page switches desktop navigation
to clusters for every role. Page-specific actions, including Add tank, stay in
their relevant page headers.

## 2026-07-27 — Make the fish directory grouped by default

**Decision:** Present fish species in collapsible care groups by default and
provide a remembered compact-list view. Store diet category separately from
free-form feeding details, expose tank usage counts, and reject deletion while
a species is assigned.

**Reason:** Grouping keeps a growing species catalog navigable, while the
compact alternative supports staff who prioritize dense operational scanning.
Structured diet and usage data make both views scannable and ensure deletion
protection is enforced by the API rather than only implied by the interface.

**Consequences:** Fish species now have `category` and `diet_type` fields, the
list contract includes `tank_count`, and existing databases require migration
`0004_fish_species_directory`.

## 2026-07-27 — Preserve operational context in fleet analytics

**Decision:** Keep fleet average as the default analytics scope, permit up to
three tank overlays, version threshold changes append-only, represent missing
buckets as nulls, and align different-unit parameter comparisons in separate
charts. Persist view state in the URL and export the visible dataset as CSV.

**Reason:** Operators need to identify which tank caused a fleet movement,
interpret readings against the rules active at that time, and distinguish
missing reports from zero values without creating misleading dual-axis charts.

**Consequences:** Analytics requests are capped at 30 days and 1,000 buckets,
threshold updates create revision records, and existing thresholds are
backfilled from the earliest known reading because earlier configuration
history cannot be reconstructed.

## Adding a decision

Use this format:

```md
## YYYY-MM-DD — Short decision title

**Decision:** What will be done.

**Reason:** Why this choice was made.

**Consequences:** What this makes easier, harder, or deferred.
```

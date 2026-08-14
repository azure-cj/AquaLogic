# AquaLogic Architecture Decisions

Status: Living decision log
Last reviewed: 2026-07-29

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

## 2026-07-28 â€” Keep species-care suitability derived and separate from alerts

**Decision:** Evaluate assigned species against a tank's latest fresh reading
on an authenticated read endpoint, with `suitable`, `attention`, and
`unavailable` results. Do not persist a species-care status or create Alert
records in this phase.

**Reason:** Species preferences are ideal ranges, not operational critical
boundaries. Dynamic evaluation reflects new readings, assignments, and range
edits immediately without derived-state synchronization or collisions with the
existing unresolved `tank_id + parameter` alert deduplication.

**Consequences:** The staff drawer owns a separate care presentation and polls
the endpoint while open. Future persistent care alerts require a category or
source, fish-species identity, a stable unresolved key, and resolution rules.

## 2026-07-28 — Dedicated staff tank workspace

**Decision:** Keep `/admin/tanks` as the configuration directory and make
`/admin/tanks/:tankId` the authenticated workspace for live operations,
Species Care, assignments, and operational alert resolution. Reuse one
configuration-only drawer from either route.

**Reason:** Operators need a bookmarkable context for one installation without
duplicating live concerns in a scanning-oriented directory.

**Consequences:** Species Care remains dynamic and distinct from operational
alerts. The detail route independently polls operations and suitability, so
their timestamps can briefly differ while sensor ingestion is in flight.

## 2026-07-29 â€” Use database-backed rotating refresh sessions

**Decision:** Issue 15-minute HS256 access JWTs only to browser memory and use
one seven-day opaque refresh token in a Strict, HttpOnly cookie. Persist only
SHA-256 refresh/setup-token hashes, active session state, user token versions,
and audit metadata.

**Reason:** A leaked access token has a short lifetime, while rotation and
session checks make sign-out, password reset, replay detection, and account
disablement immediately enforceable without browser token storage.

**Consequences:** Deployment intentionally invalidates all legacy JWTs. The
web client must bootstrap with refresh, coordinate sign-out across tabs, and
never persist authorization material. Setup links are administrator-mediated
30-minute fragments rather than temporary passwords.

## 2026-08-14 — Use a laptop bridge with fixed server-side tank mapping

**Decision:** Keep the received ESP32 firmware unchanged and use a temporary
local-laptop bridge that polls only `/data`. Authenticate the bridge with a
hash-stored device key that resolves to one registered tank; accept only the
four installed measurements.

**Reason:** The ESP32 is on the tester's LAN and must not be public or receive
staff credentials. Fixed mapping prevents a compromised bridge from selecting
another tank. Missing dissolved oxygen and ammonia are unknown, not safe zeroes.

**Consequences:** The device-provisioning response shows the raw key once,
bridge retries must tolerate tunnel outages, and dashboard statuses mark the
two deferred metrics unavailable. Direct ESP32 posting and all commands remain
deferred.

## Adding a decision

Use this format:

```md
## YYYY-MM-DD — Short decision title

**Decision:** What will be done.

**Reason:** Why this choice was made.

**Consequences:** What this makes easier, harder, or deferred.
```

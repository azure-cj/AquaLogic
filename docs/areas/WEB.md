# Web Area Guide

Status: Current
Last reviewed: 2026-10-02

## Read first

- [`../ARCHITECTURE.md`](../ARCHITECTURE.md)
- [`../API_CONTRACT.md`](../API_CONTRACT.md)
- [`../DEVELOPMENT_STATUS.md`](../DEVELOPMENT_STATUS.md)
- [`../deep-spec/phase-04-operations/`](../deep-spec/phase-04-operations/)
- [`../deep-spec/phase-05-equipment-control/`](../deep-spec/phase-05-equipment-control/)

## Important locations

- `web/src/app/`: composition, providers, router, lazy route loaders.
- `web/src/features/`: auth, fleet, alerts, tanks, fish, customers, analytics,
  staff, devices, thresholds, and public tank features.
- `web/src/features/tanks/ActuatorControlPanel.tsx`: admin-only UV, normal LED,
  feeder, and guarded Pump A/B manual-test controls, bridge freshness,
  last-known state, confirmations, and command audit history.
- `web/src/features/tanks/TankRetireDialog.tsx`: administrator confirmation for
  the one-way active-to-retired lifecycle, including bounded operational notes
  and the hardware decommissioning warning.
- `web/src/features/tanks/ActuatorControlPage.tsx`: dedicated administrator
  actuator workspace route that reuses the shared control panel in full mode.
- `web/src/features/tanks/ActuatorDirectoryPage.tsx`: administrator-only tank
  chooser linked from the Configure navigation group.
- `web/src/layouts/admin/`: persistent admin shell and navigation.
- `web/src/shared/api/`: API client and shared response models.
- `web/src/shared/components/`: reusable UI pieces, including the shared
  System/Light/Dark appearance control.
- `web/src/shared/theme/ThemeProvider.tsx`: persistent theme mode, system
  preference detection, and document-level theme application.
- `web/src/styles/`: design tokens, shared styles, and dark-theme surface
  overrides.
- `web/vercel.json`: deployment proxy configuration.

## Route boundaries

- `/tank/:publicId`: public, read-only customer experience.
- `/admin/login`, `/admin/setup-password`, `/admin/change-password`, and
  `/admin/account`, `/admin/security`: authentication, password, and
  session-management flows. Account center is the authenticated hub for
  personal security and administrator-only staff access management. Administrators
  can filter the audit feed by account, event, outcome, and date range; staff see
  only their personal sessions and no audit history. The account overview keeps
  the role-capability explanation in an accessible click/hover/focus popover so
  the page remains compact without hiding the information.
- `/admin/staff`: administrator-only staff and role management; it remains a
  stable direct route from the Account center. The workspace presents derived
  lifecycle status, activity, session counts, confirmation-gated actions, and a
  keyboard-accessible detail drawer with overview, access, sessions, and audit
  activity sections. The drawer initially renders five sessions and five
  meaningful activity items, groups routine refreshes, and provides progressive
  load-more/show-fewer controls. These controls reveal bounded client responses;
  they are not server-side pagination.
- `/admin/actuators`: administrator-only tank chooser for the focused actuator
  control route.
- `/admin/devices`: administrator-only registered-device workspace with derived
  status, fixed tank mapping, activation controls, and confirmation-gated
  one-time key rotation. The browser never persists device keys.
- Global threshold settings are labeled as defaults. The tank workspace shows
  effective values and inherited/override state; administrators can save or
  reset complete overrides while staff can view them. Global saves, tank
  override saves, and resets require confirmation and show the configuration
  scope and proposed or resulting limits. Tank units stay fixed to the
  parameter unit. Analytics shows effective bands for one selected tank
  and hides shared bands with an explicit vary-by-tank explanation when fleet
  or multi-tank histories differ. Public pages receive resulting statuses but
  never numeric threshold values. Species Care remains separate from
  operational thresholds. Threshold and alert surfaces use strict
  threshold-boundary behavior, display disabled parameters as unavailable, and
  explain that exact boundaries remain Normal. The operator-facing alert action is **Mark handled**; its legacy
  `/alerts/{alert_id}/resolve` route and `operator` resolution metadata remain
  unchanged, while automatic history continues to say automatically resolved.
  Manual handling does not confirm water recovery. The current notification
  surface is in-app only; external delivery controls are deferred.
- `/admin/*`: authenticated staff/admin experience.

Backend authorization remains authoritative. Do not rely on route visibility as a
security boundary.

The shared API client aborts requests that receive no response for 10 seconds,
so a stopped local API moves the session check to the normal login/error state
instead of leaving the application on an indefinite loading screen.

The administrator tank editor is intentionally focused on tank identity, public
profile content, hero imagery, visibility, and QR-page content. Customer
assignment remains a backend relationship but is not exposed in the demo-facing
tank form while the customer workflow is being redesigned. Hero images may use
an allowlisted HTTPS URL or, for an existing tank, an admin-only JPG/PNG/WebP
upload up to 5 MB. Uploads are served through the application media path; local
disk is a demo/local-first store and requires persistent storage or an object
storage adapter for production durability.

The fish species directory satisfies the current fish-information requirements:
authenticated directory responses expose supported preferred temperature, pH,
and TDS ranges plus safe assigned-tank summaries; the UI provides explicit
care-group, diet, and usage filters, a read-only details drawer, an admin edit
form for those ranges, and a species-photo editor with hosted URL or local
JPG/PNG/WebP upload support. Species Care is explicitly water-only: it compares
assigned species preferences with temperature, pH, and TDS and does not assess
fish compatibility, stocking density, temperament, or breeding. Its labels and
filters use water context, and stale comparisons are presented as last-known
context. Ammonia and dissolved oxygen remain deferred and are not rendered as
current-release species checks.

`/admin/tanks/:tankId` is the staff tank workspace. It independently polls
operations and Species Care, owns assignment management, and uses the shared
configuration drawer via `?edit=1`. The directory uses `?edit=:tankId` for
configuration only. Operational status uses the tank's effective monitoring
thresholds, inheriting global defaults unless overridden; Species Care is an
advisory comparison against assigned-species water
preferences. Do not reuse or alter operational-health badges for species
preference results. Offline readings remain visible as last-known values and
reporting age is derived from server receipt time, never observation time.
The tank directory defaults to active tanks and exposes Retired/All filters.
Retired detail is explicitly read-only: it retains historical readings,
alerts, assignments, configuration/media, and administrator actuator history,
uses Retired rather than Offline as its lifecycle state, hides live controls,
and exposes permanent deletion only after retirement.

The tank workspace keeps a compact administrator-only actuator snapshot with
bridge freshness, last-known actuator states, safe quick actions, and a link to
`/admin/tanks/:tankId/actuators`. The dedicated route is the full actuator
control center for the registered tank: timers, schedules, feeder
configuration, guarded Pump A/B manual tests, offline/expiry warnings, and
paginated command history remain there. It loads the tank and actuator APIs only
after the existing `/auth/me` response confirms an administrator; staff see a
restriction notice and the backend remains the enforcement point.

The Configure navigation group includes an administrator-only **Actuators**
entry beside **Thresholds**. Its chooser lists tanks from the authenticated
tank directory and links to the selected tank’s focused control route; it does
not select a device or bypass the backend’s fixed device-to-tank mapping.

The administrator retirement dialog explains that the tank leaves live and
public operations, disables registered devices, and retains history; it asks
for an optional bounded note and points to the hardware checklist. The
retired detail's permanent-delete warning then enumerates the same relational,
media, and public-page consequences. Both administrator tank deletion entry
points use the expanded warning:
sensor readings, alerts, equipment command/state history, device registrations,
species assignments, the uploaded tank image, and the public tank page are
removed, and the action cannot be undone. The warning does not claim that
ESP32 schedules or physical equipment state are cleared; operators must follow
the [tank decommissioning workflow](../WORKFLOWS.md#tank-deletion-and-hardware-decommissioning)
before deletion. The separate [device move workflow](../WORKFLOWS.md#moving-equipment-to-another-tank)
uses new provisioning rather than reassignment.

Ammonia and dissolved oxygen are deferred from the current software release
and are hidden from the thresholds UI, along with other demo-facing controls.
They remain nullable in API responses for future integration, but are not
rendered in the tank workspace, fleet view, public tank page, analytics
selectors, or Species Care checks. The web does not create UI charts or alerts
for those deferred values.

The full actuator control center renders actuator controls only after the
authenticated user is known to be an admin. It polls the admin-only actuator
status route and the bounded, paginated history route, shows last-known state plus bridge
online/offline freshness, and requires a confirmation dialog before **Feed now**.
History provides newest-first page metadata, previous/next navigation, and
actuator/status filters, and fixed-device lifecycle summary counts including
`outcome_unknown`. The audit
explanation is available from a keyboard-accessible custom tooltip rendered at
the document level so panel overflow cannot clip it, keeping the history header
compact. Larger row typography, human-readable actuator/action labels, and
expandable details make the audit trail understandable without exposing raw
configuration. Expired commands have a distinct purple status treatment and a
`Never sent` badge because they were not delivered to the ESP32. Each row explains whether the command is still
waiting, may be in progress, reported physical endpoint success, confirmed
failure, outcome unknown, or expired before bridge execution. An offline/stale bridge warning explains that
newly queued commands may expire. Control feedback is rendered in a page-level
toast rail below the floating navigation so it is not clipped by the
overflow-hidden actuator panel or overlap the navbar; successful queue notices
auto-dismiss while failures remain until dismissed. Staff sees a non-usable
restriction notice and the browser does not fetch actuator endpoints; backend
authorization remains authoritative and returns 403 for staff actuator requests.

Pump cards are explicitly labeled as manual dry-run tests, require an online
bridge, show the firmware-reported configured dispense volume in mL, show a
visible Stop action, and require confirmation before Dispense/Test or Retract.
An executing or uncleared `outcome_unknown` same-device/same-pump dispense
lock disables only another Dispense/Test action. Stop remains available;
Retract remains a deliberate maintenance action and does not clear the lock.
Administrators can record physical verification through a confirmation-gated
action; the UI
keeps the historical command Outcome unknown and explains that verification
does not prove the exact dose.
The UI explains that the tester bridge must have `pump_manual_test_enabled:
true` only during empty-syringe or water-only checks; pump schedules, pH
auto-dose, and automatic dosing are not rendered. The current firmware does not
expose an editable volume endpoint, so the UI does not accept a misleading
seconds or milliseconds dose input.

The web client never receives an ESP32 URL or device key. It queues commands at
the AquaLogic backend, which hands them to the existing local-only bridge.

UV, normal LED, and feeder schedule forms configure device-resident schedules;
the web client does not run a scheduler or display each future autonomous event
as a separate command. A successful request means the device accepted the
configuration command, while a stale bridge report remains last-known context
and does not guarantee the physical actuator is off.

The public tank route bundles its DM Sans, Source Sans 3, and Libre Baskerville
faces locally through Fontsource. Keep those font variables scoped beneath
`.visitor-shell` so the staff dashboard retains its Geist typography.

The web client supports System, Light, and Dark appearance modes. The selected
mode is stored only as the non-sensitive `aqualogic-theme` browser preference;
authentication state and device credentials are not stored there. The shared
appearance control is available in the admin navbar, authentication card, and
public tank header. The bootstrap in `web/index.html` applies the saved/system
mode before React renders to prevent a theme flash. Keep new surfaces on the
semantic tokens and update `dark-theme.css` when a feature introduces a
hardcoded light-only color. A short teal ink-bloom transition starts at the
appearance control for deliberate mode changes; `prefers-reduced-motion` turns
the bloom and color transitions off.

The API client keeps access tokens in module memory only. It performs one
single-flight `/auth/refresh` request and one retry for an expired authenticated
request; refresh failure clears React Query data and broadcasts sign-out to
other tabs. Do not add browser storage for authentication state.

`/admin/security` is a compact account-security center: it shows readable
device summaries, keeps raw user-agent strings behind technical details,
requires an explicit confirmation before revoking another session, and expands
the password-confirmed sign-out-everywhere form only after intent. The
administrator audit feed groups routine refresh events so account-changing
events remain scannable. Administrators can filter it by account, event,
outcome, and date range; bridge telemetry is also grouped in the default feed.
Staff never receive the administrator-only audit feed. Signed-in device cards
show both activity and expiry context so an operator can distinguish a recently
used session from one nearing expiry.

The `/admin/alerts` water-quality history view uses server-side pagination with
25 rows per page and preserves filters plus the current page in the URL. The
backend returns page totals and stable newest-first ordering when `page` or
`page_size` is supplied. Calls that omit both parameters retain the legacy list
response used by the mobile client. The web request filters deferred metrics on
the server before counting and paging.

## Common checks

```powershell
cd web
npm run typecheck
npm test
npm run build
```

For actuator UI coverage, also run:

```powershell
cd web
npm test -- --run src/features/tanks/ActuatorControlPanel.test.tsx
```

Use the existing `@/` import alias and feature-first structure when adding a
page. Keep route-specific code lazy-loaded through `web/src/app/route-loaders.ts`.
# Alert detail update — 2026-10-02

`features/alerts/AlertDetailDrawer.tsx` is shared by alert history and tank
active/history entries. Fleet alert links pass `alert_id` to alert history;
filter synchronization preserves that parameter. Context loads only on open.
Handling refreshes detail and operational caches. Staff equipment navigation
uses the tank Control access explanation; administrator navigation uses the
existing actuator workspace. Analytics is disabled pending version
reconciliation described in [M0/M1](../M0_M1_OPERATOR_GUIDANCE.md).

## M2/M3 investigation UI (2026-10-02)

The shared alert drawer adds optional current species counts/individual stored
preferences and enables the verified tanks/metric Analytics URL. Reconciled
Analytics retains fixed half-hour observations, partial tooltips and Refresh.
`DecisionSupportInsights.tsx` renders four named-tank historical cards plus
expansion/limitations and graph/real-alert navigation. Absent additive fields
remain readable. `vite.review.config.ts` is used only by the isolated launcher;
normal Vercel API routing remains intact. See [implementation](../M2_M3_IMPLEMENTATION.md).

## 2026-10-02 - Operator UI design pass

Web Analytics now places the main trend chart before historical findings. Findings
use padded two-column cards (one column on narrow screens), metric labels,
prominent observation percentages with one decimal at most, and expandable
evidence. Fully within-range observations and their little-change findings are
grouped separately; abnormal little-change findings remain in the primary list.
Bounds-change disclosures remain visible. View graph selects the tank/metric
and scrolls to the chart while retaining the timeframe.

The shared alert drawer compares linked/latest readings, puts numbered suggested
checks before expandable historical bounds/species detail, and uses the existing
fixed drawer footer for navigation and handling. Unsupported turbidity species
context uses one explanation. API calculations and alert lifecycle are unchanged.

Validation: web typecheck/build and 133 tests passed. Actual synthetic API/UI
checked at 1440px and 320px, in light and dark appearance; narrow document width
remained 320px. Screenshots are under evidence/operator-guidance/ui-*.png.
This pass covers the web views shown in the review screenshots.


### 2026-10-02: Approved Analytics hybrid layout

The chart-led overview and compact three-tank findings rail replace the earlier
large findings-card grid. Metric tabs and observation summaries live with the
main chart; its legend and threshold-scope explanation sit below it.

Tank comparison provides Observation evidence, Reporting, and Alert records
tabs. Rows retain tank/parameter scope, evidence counts, bounds-change notices,
unavailable values, and expandable full qualifications. Eight rows show initially;
additional rows remain available. Receipt coverage remains distinct from
observation percentages. Selected-tank findings and fleet totals retain their
existing API scopes. View graph retains the timeframe.

The lower alert chart and three-tank reporting preview use their own content
heights. Narrow tables stack into labelled rows; light and dark themes use the
existing semantic tokens. Backend calculations and alert lifecycle are unchanged.

Validation: 137 tests across 27 web test files, typecheck, and production build
passed. Actual synthetic UI checked at 1440px and 320px, including dark appearance,
evidence-to-graph navigation, reporting/alert tabs, and no browser console errors.
Narrow document width remained 320px. Screenshots: docs/evidence/analytics-concepts/
implemented-*.png. This is a local web change, with no deployment.


### 2026-10-02: Operator-friendly Analytics copy and disclosure

Current Analytics uses Key findings, Water quality, Data availability, Alerts,
Readings in range, Readings analyzed, and View details. Findings lead with plain
language and exact reading counts. Chart summaries use API-qualified tank
findings only; insufficient evidence never becomes a stable trend.

How this is calculated retains original finding text, all evidence values,
qualifications, exclusions, interval coverage and observation dates. Range-change
warnings and nonzero range exclusions remain visible in expanded results.
Reporting details retain current/previous percentages and receipt interval counts.
About these results appears after other parameters, explains fixed half-hour
observation buckets, partial buckets, threshold history, receipt-time coverage,
and reporting gaps. Current-parameter limitations appear first; other parameters'
notes remain available in a nested disclosure. No API/backend calculation or
semantics changed in this pass; no firmware/bridge/pump/monitoring changes.

Validation: focused Analytics suite 20 tests passed; full web suite 140 tests in
27 files passed; typecheck, production build and git diff --check passed.
Browser checked pH counts (29 in range, 12 outside, 41 analyzed), disclosures,
reporting tab and responsive 320px layout without horizontal document overflow.
Console errors: none. Screenshots: evidence/analytics-concepts/operator-*.png.


### 2026-10-03: Analytics information consolidation

Current hierarchy follows one fact, one primary place. Key findings groups
similar results across tanks (at most three distinct categories), with three
initial tank links and disclosure for more. Routine within-range findings stay
in the table when noteworthy categories are available. No finding is discarded:
all original cards, qualifications, checks, values and limitations remain in the
technical evidence surface.

Water quality rows hold range percentages and analyzed counts; per-tank receipt
availability belongs only in the Data availability tab. Expanded water-quality
rows show one essential evidence set, dates, exclusions when relevant, and
range-change/late-arrival notes. The standalone availability card summarizes
fleet completeness without a repeated tank list. About these results opens to
four short notes; View technical details contains methodology, interval rules,
full per-parameter evidence and limitations. Graphs and backend rules unchanged.

Validation: 21 focused Analytics tests and 141 full web tests in 27 files passed.
Typecheck, production build and git diff --check passed. Hash comparison confirmed
backend Python files and Analytics types/utilities unchanged during this pass.
Browser confirmed compact details, grouped temperature findings, access to exact
pH evidence/limitations and no console errors. Screenshot:
evidence/analytics-concepts/consolidated-overview.png.

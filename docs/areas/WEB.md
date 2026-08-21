# Web Area Guide

Status: Current
Last reviewed: 2026-08-21

## Read first

- [`../ARCHITECTURE.md`](../ARCHITECTURE.md)
- [`../API_CONTRACT.md`](../API_CONTRACT.md)
- [`../DEVELOPMENT_STATUS.md`](../DEVELOPMENT_STATUS.md)
- [`../WEB_DASHBOARD_IMPLEMENTATION_REPORT.md`](../WEB_DASHBOARD_IMPLEMENTATION_REPORT.md)

## Important locations

- `web/src/app/`: composition, providers, router, lazy route loaders.
- `web/src/features/`: auth, fleet, alerts, tanks, fish, customers, analytics,
  staff, devices, thresholds, and public tank features.
- `web/src/features/tanks/ActuatorControlPanel.tsx`: admin-only UV, normal LED,
  feeder, and guarded Pump A/B manual-test controls, bridge freshness,
  last-known state, confirmations, and command audit history.
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
- Threshold and alert surfaces use strict threshold-boundary behavior, display
  disabled parameters as unavailable, and label resolved alerts as
  operator-resolved or automatically resolved when the additive API metadata is
  present. The current notification surface is in-app only; external delivery
  controls are deferred.
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
JPG/PNG/WebP upload support. Species Care compares assigned species with the
tank's latest supported reading and labels suitable, needs-attention, and
insufficient-data states. Ammonia and dissolved oxygen remain deferred and are
not rendered as current-release species checks.

`/admin/tanks/:tankId` is the staff tank workspace. It independently polls
operations and Species Care, owns assignment management, and uses the shared
configuration drawer via `?edit=1`. The directory uses `?edit=:tankId` for
configuration only. Do not reuse or alter operational-health badges for
species preference results.

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
actuator/status filters, and fixed-device lifecycle summary counts. The audit
explanation is available from a keyboard-accessible custom tooltip rendered at
the document level so panel overflow cannot clip it, keeping the history header
compact. Larger row typography, human-readable actuator/action labels, and
expandable details make the audit trail understandable without exposing raw
configuration. Expired commands have a distinct purple status treatment and a
`Never sent` badge because they were not delivered to the ESP32. Each row explains whether the command is still
waiting, may be in progress, reported physical endpoint success, failed, or
expired before bridge execution. An offline/stale bridge warning explains that
newly queued commands may expire. Control feedback is rendered in a page-level
toast rail below the floating navigation so it is not clipped by the
overflow-hidden actuator panel or overlap the navbar; successful queue notices
auto-dismiss while failures remain until dismissed. Staff sees a non-usable
restriction notice and the browser does not fetch actuator endpoints; backend
authorization remains authoritative and returns 403 for staff actuator requests.

Pump cards are explicitly labeled as manual dry-run tests, require an online
bridge, show the firmware-reported configured dispense volume in mL, show a
visible Stop action, and require confirmation before Dispense/Test or Retract.
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

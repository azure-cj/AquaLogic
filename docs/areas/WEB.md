# Web Area Guide

Status: Current
Last reviewed: 2026-08-15

## Read first

- [`../ARCHITECTURE.md`](../ARCHITECTURE.md)
- [`../API_CONTRACT.md`](../API_CONTRACT.md)
- [`../DEVELOPMENT_STATUS.md`](../DEVELOPMENT_STATUS.md)
- [`../WEB_DASHBOARD_IMPLEMENTATION_REPORT.md`](../WEB_DASHBOARD_IMPLEMENTATION_REPORT.md)

## Important locations

- `web/src/app/`: composition, providers, router, lazy route loaders.
- `web/src/features/`: auth, fleet, alerts, tanks, fish, customers, analytics,
  staff, thresholds, and public tank features.
- `web/src/features/tanks/ActuatorControlPanel.tsx`: admin-only UV, normal LED,
  feeder, and guarded Pump A/B manual-test controls, bridge freshness,
  last-known state, confirmations, and command audit history.
- `web/src/layouts/admin/`: persistent admin shell and navigation.
- `web/src/shared/api/`: API client and shared response models.
- `web/src/shared/components/`: reusable UI pieces.
- `web/src/styles/`: design tokens and shared styles.
- `web/vercel.json`: deployment proxy configuration.

## Route boundaries

- `/tank/:publicId`: public, read-only customer experience.
- `/admin/login`, `/admin/setup-password`, `/admin/change-password`, and
  `/admin/account`, `/admin/security`: authentication, password, and
  session-management flows. Account center is the authenticated hub for
  personal security and administrator-only staff access management.
- `/admin/staff`: administrator-only staff and role management; it remains a
  stable direct route from the Account center.
- `/admin/*`: authenticated staff/admin experience.

Backend authorization remains authoritative. Do not rely on route visibility as a
security boundary.

`/admin/tanks/:tankId` is the staff tank workspace. It independently polls
operations and Species Care, owns assignment management, and uses the shared
configuration drawer via `?edit=1`. The directory uses `?edit=:tankId` for
configuration only. Do not reuse or alter operational-health badges for
species preference results.

The tank workspace labels missing dissolved oxygen and ammonia values as **Not
installed** and uses the operations response freshness state for stale/offline
bridge readings.

The tank workspace renders actuator controls only after the authenticated user is
known to be an admin. It polls the admin-only actuator status route and the
bounded, paginated history route, shows last-known state plus bridge
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
bridge, offer only bounded dispense durations, show a visible Stop action, and
require confirmation before Dispense/Test or Retract. The UI explains that the
tester bridge must have `pump_manual_test_enabled: true` only during empty-
syringe or water-only checks; pump schedules, pH auto-dose, and automatic dosing
are not rendered.

The web client never receives an ESP32 URL or device key. It queues commands at
the AquaLogic backend, which hands them to the existing local-only bridge.

The public tank route bundles its DM Sans, Source Sans 3, and Libre Baskerville
faces locally through Fontsource. Keep those font variables scoped beneath
`.visitor-shell` so the staff dashboard retains its Geist typography.

The API client keeps access tokens in module memory only. It performs one
single-flight `/auth/refresh` request and one retry for an expired authenticated
request; refresh failure clears React Query data and broadcasts sign-out to
other tabs. Do not add browser storage for authentication state.

`/admin/security` is a compact account-security center: it shows readable
device summaries, keeps raw user-agent strings behind technical details,
requires an explicit confirmation before revoking another session, and expands
the password-confirmed sign-out-everywhere form only after intent. The
administrator audit feed groups routine refresh events so account-changing
events remain scannable.

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

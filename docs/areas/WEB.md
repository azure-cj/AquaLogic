# Web Area Guide

Status: Current
Last reviewed: 2026-07-29

## Read first

- [`../ARCHITECTURE.md`](../ARCHITECTURE.md)
- [`../API_CONTRACT.md`](../API_CONTRACT.md)
- [`../DEVELOPMENT_STATUS.md`](../DEVELOPMENT_STATUS.md)
- [`../WEB_DASHBOARD_IMPLEMENTATION_REPORT.md`](../WEB_DASHBOARD_IMPLEMENTATION_REPORT.md)

## Important locations

- `web/src/app/`: composition, providers, router, lazy route loaders.
- `web/src/features/`: auth, fleet, alerts, tanks, fish, customers, analytics,
  staff, thresholds, and public tank features.
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

Use the existing `@/` import alias and feature-first structure when adding a
page. Keep route-specific code lazy-loaded through `web/src/app/route-loaders.ts`.

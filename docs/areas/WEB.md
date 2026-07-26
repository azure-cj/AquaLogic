# Web Area Guide

Status: Current
Last reviewed: 2026-07-27

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
- `/admin/login` and `/admin/change-password`: auth flow.
- `/admin/*`: authenticated staff/admin experience.

Backend authorization remains authoritative. Do not rely on route visibility as a
security boundary.

## Common checks

```powershell
cd web
npm run typecheck
npm test
npm run build
```

Use the existing `@/` import alias and feature-first structure when adding a
page. Keep route-specific code lazy-loaded through `web/src/app/route-loaders.ts`.

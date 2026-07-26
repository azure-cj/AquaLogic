# AquaLogic web dashboard implementation report

Last updated: July 27, 2026

## Current checkpoint

The customer-facing tank experience and staff web dashboard are implemented locally and integrated with the existing FastAPI backend. The admin interface now uses the AquaLogic Operational Command Center design and a feature-first React source structure.

This checkpoint covers local implementation and validation only. No Vercel, Render, or Supabase deployment has been performed.

## Completed functionality

### Public customer web

- Mobile-first `/tank/:publicId` experience with no authentication requirement.
- Public tank identity, location, habitat details, water type, volume, establishment date, and optional hero image.
- Current water status and parameter-level status wording for temperature, pH, turbidity, dissolved oxygen, TDS, and ammonia.
- Offline, no-reading, private/not-found, no-fish, and missing-image states.
- Fish species cards, feeding information, visitor guidance, care notes, FAQ content, and accessible in-page navigation.
- UUID-based public URLs suitable for tank QR labels.

### Admin web

- Staff login, JWT session validation, sign-out, forced password change, and role-aware navigation.
- Operational Command Center fleet overview with 30-second refresh, status filtering, tank readings, active alert totals, recent alerts, and reporting uptime.
- Reporting uptime ranges for 24 hours, 7 days, and 30 days.
- Alert history with severity, parameter, state, date, and tank filters plus resolution feedback.
- Tank management with customer assignment, fish assignment/removal, public preview, URL copying, QR preview/download/print, and deletion controls.
- Fish species and customer CRUD workflows using accessible side panels and confirmation dialogs.
- Analytics for temperature, pH, turbidity, dissolved oxygen, TDS, ammonia, alert frequency, and per-tank reporting uptime.
- Staff creation, role/status changes, temporary password reset, and one-time password copying.
- Per-parameter threshold configuration with units, enabled state, validation feedback, and independent save progress.
- Manila-local dates, relative operational times, keyboard-accessible dialogs and drawers, visible focus states, responsive layouts, and non-color status labels.

### Backend and database

- Public tank UUID, public visibility, display metadata, feeding schedule, care notes, customer ownership, threshold configuration, alert audit fields, and staff password-change state.
- Unified sensor ingestion and alert decision handling.
- Fleet, filtered alert history, management, threshold, public tank, and fleet analytics endpoints.
- Reporting uptime now counts unique 30-second reporting intervals rather than raw reading rows.
- Analytics returns current and previous equivalent-period uptime so the web can display a genuine increase or decrease.
- Production CORS rejects wildcard configuration.
- Demo ingestion requires both the global demo flag and the designated-instance flag.
- Alembic migrations:
  - `0001_initial.py`
  - `0002_web_dashboard.py`
  - `0003_public_tank_experience.py`

## Frontend architecture

The React application now uses a feature-first layout:

```text
web/src/
  app/                  # App composition, routing, route loaders, providers
  features/             # Auth, fleet, alerts, tanks, fish, customers,
                        # analytics, staff, thresholds, and public tank pages
  layouts/admin/        # Persistent admin shell and navigation
  shared/api/           # API client and shared response models
  shared/components/    # Reusable admin UI and resource manager
  shared/hooks/         # Shared query/session hooks
  shared/utils/         # Date, reading, and display formatting
  styles/               # Tokens, base styles, and shared admin styles
```

- The previous monolithic `pages.tsx` and `dashboard.css` files were removed.
- TypeScript and Vite use the `@/` alias for source imports.
- Every public, authentication, and admin page is route-based and lazy-loaded.
- The admin shell remains mounted during page transitions.
- Navigation hover, keyboard focus, and touch intent prefetch the destination chunk.
- Slow first loads show a canvas-matched content skeleton instead of replacing the full admin layout with a light fallback.
- Feature-specific JavaScript and CSS remain separate production chunks; Recharts stays isolated with the analytics route.

## Routes and authorization

### Browser routes

```text
/tank/:publicId
/admin/login
/admin/change-password
/admin/fleet
/admin/alerts
/admin/tanks
/admin/tanks/:tankId
/admin/fish
/admin/customers
/admin/analytics
/admin/staff
/admin/settings/thresholds
```

### Authorization

- `/tank/:publicId` and `GET /public/tanks/{public_id}` are public.
- Authenticated staff with completed password changes can access fleet, alerts, tanks, fish, customers, analytics, and threshold reads.
- Staff/user management and threshold writes require the admin role.
- Temporary-password users are redirected to password change before accessing the dashboard.
- Inactive users cannot authenticate or continue using an existing JWT.

## Key implementation files

- `backend/app/routes/dashboard.py`
- `backend/app/routes/management.py`
- `backend/app/routes/public.py`
- `backend/app/services/decision_engine.py`
- `web/src/app/router.tsx`
- `web/src/app/route-loaders.ts`
- `web/src/layouts/admin/AdminShell.tsx`
- `web/src/features/`
- `web/src/shared/`
- `render.yaml`
- `web/vercel.json`

## Validation record

Recommended local validation:

```powershell
cd backend
pytest -q
alembic upgrade head

cd ..\web
npm install
npm run typecheck
npm test
npm run build
```

Latest recorded results:

- Backend tests: **11 passed** with one third-party multipart deprecation warning.
- Alembic: **passed** through the latest migration against a fresh temporary database.
- Frontend typecheck: **passed**.
- Frontend strict unused-import check: **passed**.
- Frontend tests: **29 passed across 7 test files**.
- Frontend production build: **passed**.
- Initial production JavaScript: approximately **230 kB** before gzip.
- Analytics/Recharts route chunk: approximately **388 kB** before gzip and loaded only when needed.
- Separate route-level JavaScript and CSS chunks: **confirmed**.

Earlier browser smoke validation passed on isolated local API/web instances:

- Admin login reached `/admin/fleet` with seeded tanks.
- A public UUID page rendered offline, no-reading, and no-fish states without authentication.

The browser smoke result predates the latest source-organization and loading-transition refactors. Typecheck, component/router tests, and the production build were rerun afterward; a complete visual browser regression pass remains a follow-up.

## Deployment status and checklist

Deployment configuration exists, but cloud resources have not been provisioned.

1. Create a PostgreSQL database and set `DATABASE_URL` for the backend service.
2. Configure a unique JWT secret, explicit production CORS origins, public base URL, and controlled initial-admin values.
3. Create the Render API service from `render.yaml`; its pre-deploy command runs Alembic.
4. Replace `YOUR-RENDER-SERVICE` in `web/vercel.json`.
5. Deploy `web/` to Vercel with `VITE_API_BASE_URL=/api`.
6. Keep demo sensor ingestion disabled unless one designated API instance explicitly enables both required flags.
7. Run production login, public QR, CORS, migration, and sensor-ingestion smoke tests after deployment.

## Known limitations and follow-up

- List endpoints do not yet provide pagination for large fleets, alerts, customers, fish, or staff datasets.
- Fleet analytics currently loads and aggregates the selected period in application memory; database-level aggregation or rollups will be needed at larger data volumes.
- The production PostgreSQL/Render/Supabase path has not been exercised; current migration validation used a temporary local database.
- JWT security can be strengthened with explicit revocation/versioning, refresh-token rotation, and secret-rotation procedures.
- The public tank endpoint intentionally exposes the latest configured sensor values; the final production privacy and threat review must confirm that this is acceptable.
- Staff management does not yet prevent demoting or deactivating the final active administrator.
- A complete browser regression pass is still needed for all admin routes, responsive breakpoints, QR printing, and the public tank page after the latest frontend refactor.
- CI should run backend tests, frontend typecheck/tests/build, migration validation, and browser smoke coverage.
- E-commerce, inventory, and customer transactions remain outside the current project scope.

# Mobile Area Guide

Status: M1 backend authentication integrated; operational data remains mock-backed
Last reviewed: 2026-09-25

## Read first

- [`../PROJECT_CONTEXT.md`](../PROJECT_CONTEXT.md)
- [`../ARCHITECTURE.md`](../ARCHITECTURE.md)
- [`../API_CONTRACT.md`](../API_CONTRACT.md)
- [`../DEVELOPMENT_STATUS.md`](../DEVELOPMENT_STATUS.md)

## Current boundary

The Flutter app is an Android-first client. Authentication talks directly to
the Railway FastAPI service through one shared HTTP client. Home, tank, alert,
fish, equipment, and operational account data still use deterministic local
demo data behind the existing repository seams. No sensor or device connection
is made by the mobile app.

## M1 authentication integration

Implemented:

- AquaLogic-branded Flutter sign-in screen with validation, password visibility,
  loading, keyboard submission, safe API error messages, and Retry-After display
  for sign-in throttling.
- `ApiAuthService` is the default app composition; tests can still inject
  `MockAuthService` through `AquaLogicApp(authService: ...)`.
- `ApiClient` centralizes URL selection, JSON, bounded request timeouts,
  normalized failures, bearer headers, and one single-flight refresh retry for
  protected requests.
- Release builds default to the Railway root API URL. Debug builds default to
  Android emulator alias `10.0.2.2:8000`; physical-device development can
  override `AQUALOGIC_API_BASE_URL` with the developer machine's LAN URL.
- Access JWTs and expiry are memory-only. The opaque refresh-cookie value is
  stored through Android secure storage, sent only to `/auth/refresh`, and
  replaced when the backend rotates it.
- Cold start refreshes the session and loads `/auth/me`; invalid refresh
  sessions return to Login, while network failures preserve the credential and
  show a retry state.
- A forced password-change status gates the shell until `/auth/change-password`
  succeeds. Logout revokes the server session when reachable and always clears
  local auth state.
- Local development Owner/admin and Staff accounts in
  [`MockAuthService`](../../mobile_app/lib/features/auth/data/mock_auth_service.dart).
- An authenticated user model that preserves the backend-compatible `admin` and
  `staff` role values while presenting `Owner` and `Staff` labels in the mobile
  UI.
- An app-level auth state, `AuthGate`, shared authenticated shell, role-aware
  identity treatment, and sign-out from More/Account.

Development accounts:

| Experience | Email | Password | Backend role |
| --- | --- | --- | --- |
| Owner | `owner@aqualogic.local` | `owner123` | `admin` |
| Staff | `staff@aqualogic.local` | `staff123` | `staff` |

These are local prototype credentials only and are not production security.

Still mock-backed / not implemented:

- Home, Tanks, Alerts, Monitoring, species, equipment, and operational account
  repositories are not connected to Railway.
- Profile editing and server-side data synchronization are not implemented.
- Physical actuator commands, push notifications, and background refresh are
  not implemented.

## Role-Aware Home V1

Implemented:

- Owner Home focused on fleet condition, exceptions, compact fleet overview,
  monitoring/reporting state, and recent activity.
- Staff Home focused on the same compact highest-priority attention card,
  monitoring/reporting state, tank rounds, and recent activity.
- Shared Home components for role headers, operational status badges, attention
  cards, tank rows, monitoring summaries, and activity rows.
- Backend-compatible operational status presentation: `Normal`, `Warning`,
  `Critical`, and `Offline`. Offline remains separate from water-quality
  attention, and monitoring state remains separate from Alerts.
- Lightweight Home presentation models and a local `MockHomeRepository` so the
  UI can later receive equivalent data from an API repository.

The primary Home no longer uses a fabricated health percentage as its
operational summary. The former Owner Brief/pager was retired from the main
Home flow because it duplicated the overview and centered that percentage.

## Mobile UI/UX refinement milestone

Implemented locally in the Flutter prototype:

- A four-tab authenticated shell: Home, Tanks, Alerts, and More. Equipment is
  contextual to an Owner's tank rather than a top-level destination. Its
  bottom navigation is a safe-area-aware floating dock that stays over page
  content, hides on intentional downward scrolling, and restores on upward
  scrolling or tab selection without resizing the page.
- Tanks directory filters for all, needs attention, and offline; compact tank
  cards; tank detail sections; freshness labels; normal/warning/critical/offline
  operational semantics; and responsive current-reading cards for temperature,
  pH, turbidity, and TDS.
- Tank detail separation between water-quality issues and monitoring/reporting
  issues, with species snapshots, suitability states, lifecycle labeling, and
  recent activity. Retired tanks use a dedicated lifecycle label and are not
  collapsed into Offline, a health score, or an alert severity.
- Alerts split into Water quality and Monitoring streams, each with Active and
  History views. Water-quality alerts use warning/critical severity; monitoring
  outages are neutral operational incidents and cannot be manually resolved.
  Mark handled is local acknowledgement only and does not claim recovery.
- Fish species directory and detail screens with search, freshwater/saltwater
  filters, preferred water ranges, care notes, assigned-species context, and
  suitable/attention/unavailable suitability states kept distinct from
  operational alerts.
- Contextual Owner Equipment for UV, LED, automatic feeder, Pump A, and Pump B.
  Device connectivity is shown separately from device state. Owner commands
  use safe confirmations and a deterministic local lifecycle of queued,
  executing, succeeded, failed, expired, or outcome unknown. Staff see a
  read-only equipment view with no write controls.
- More/Account, Sync/local data, About, identity, role, and sign-out surfaces.
  Fake notification, haptic, and critical-only settings were removed.
- Shared semantic badges, freshness labels, section headers, empty states, and
  repository seams that keep future asynchronous/API work out of the widgets.

The local mock repositories are `MockTankRepository`, `MockAlertRepository`,
`MockFishRepository`, and `MockEquipmentRepository`. They intentionally do not
replace the FastAPI contract; they provide a stable UI seam for this milestone
and can later be replaced by API-backed repositories.

## Startup experience refinement

Implemented in the Flutter prototype:

- Android and Flutter launch surfaces use the same pale aqua base and existing
  AquaLogic mark. Flutter then fades in the supplied light underwater artwork,
  brand, a restrained custom-painted waterline, and four sparse ambient bubbles.
- Startup shows one static `Preparing AquaLogic` label. It does not simulate
  backend progress or show a progress bar, rotating status text, or moving fish.
- The 600 ms minimum display window is a visual continuity floor. The splash
  stays visible while `AuthService` is checking and then hands off through the
  existing `AuthGate` to its selected Login or authenticated destination.
- Reduced-motion mode disables bubble and waterline animation and keeps the
  logo/scene handoff to opacity transitions. Controllers and the minimum timer
  are disposed with the splash state.

Production auth resolves through session restore, Login, or a retryable
connection state; the splash does not claim backend progress. Tests can inject
`MockAuthService` and retain deterministic startup. Focused behavior tests live in
[`splash_screen_test.dart`](../../mobile_app/test/splash_screen_test.dart).

## Deferred integration work

The following remain outside this milestone:

- Live sensor sync, persisted alert and monitoring-incident queries, sensor
  history, backend freshness calculations, and offline cache/sync conflict
  handling.
- Backend species-directory and assignment APIs.
- Real actuator commands, device connectivity, command reconciliation, and
  production equipment safety controls.
- Push notifications, background workers, and external monitoring delivery.

When feature repositories move to live data, update this guide, the API
contract, and the development status together. Keep mock data clearly labeled
as mock-backed until each repository is replaced.

## Important locations

- `mobile_app/lib/app/`: app composition, theme, navigation, and startup.
- `mobile_app/lib/app/auth/`: auth scope and the startup authentication gate.
- `mobile_app/lib/features/auth/`: API and mock auth services, secure refresh
  storage, user and role models, forced password-change gate, and login screen.
- `mobile_app/lib/features/home/`: role-aware Home compositions, local Home
  presentation models/data, and shared Home widgets.
- `mobile_app/lib/features/tanks/`: tank directory, detail, readings, issues,
  lifecycle, and the mock tank repository.
- `mobile_app/lib/features/alerts/`: water-quality and monitoring alert models,
  mock repository, list/detail views, and handling semantics.
- `mobile_app/lib/features/fish/`: species directory, detail, suitability, and
  mock fish repository.
- `mobile_app/lib/features/control/`: contextual Equipment models, mock
  repository, command lifecycle, and Owner/Staff equipment view.
- `mobile_app/lib/features/more/`: account, local-data, and about surfaces.
- `mobile_app/lib/shared/`: shared status models, badges, freshness labels,
  empty states, and layout primitives.
- `mobile_app/lib/shared/network/`: API configuration, shared HTTP client, and
  normalized API failures.
- `mobile_app/test/`: widget and repository/semantics tests.
- `mobile_app/pubspec.yaml`: Flutter dependencies and assets.

## Common checks

```powershell
cd mobile_app
flutter pub get
flutter analyze
flutter test
```

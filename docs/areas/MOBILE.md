# Mobile Area Guide

Status: M6.2 authenticated device registration verified on Railway and a physical Android installation; M6.3 FID sender is deployed, with an Android FCM-registration correction in progress after the first production test was rejected; M6.4 remains gated on physical re-registration and one successful test push; M6.5 event triggers and M6.6 navigation have not started
Last reviewed: 2026-09-26

## Read first

- [`../PROJECT_CONTEXT.md`](../PROJECT_CONTEXT.md)
- [`../ARCHITECTURE.md`](../ARCHITECTURE.md)
- [`../API_CONTRACT.md`](../API_CONTRACT.md)
- [`../DEVELOPMENT_STATUS.md`](../DEVELOPMENT_STATUS.md)

## Current boundary

The Flutter app is an Android-first client. Authentication, Home, Tanks, Alerts,
Monitoring, species, and read-only equipment talk directly to the Railway
FastAPI service through the shared authenticated `ApiClient`. Account identity
comes from `/auth/me`; no profile-edit API is connected. The app does not
connect directly to a sensor or device.

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

- Profile editing and organization/customer profile synchronization are not
  implemented; account identity and role come from `/auth/me`.
- Recent activity and historical sensor readings/charts are not available from
  the mobile API slice. Tank Detail omits mock-only activity for live data.
- Physical actuator commands and background refresh are not implemented.
  M6.1 added the Flutter FCM client foundation, M6.2 authenticated device
  registration is verified, and M6.3 backend sending has deployed. The Android
  FID-registration correction and M6.4 physical send gate remain active.
  Production alert/monitoring triggers remain
  deferred to M6.5. Species and read-only equipment use Railway repositories
  under M5, described below.

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

## M2 live Home integration

`ApiHomeRepository` uses the M1 authenticated client for three concurrent,
read-only requests: `GET /fleet`, `GET /alerts` (unresolved by default), and
`GET /monitoring-incidents?state=active&page=1&page_size=100`. Fleet is required;
alert and monitoring detail failures are represented as partial data while the
fleet remains visible. Monitoring outage totals use the endpoint's exact
paginated `total`, and the newest page supplies detail for the priority card.
If the incident request fails, the per-tank fleet incident counts remain the
safe count fallback.

Backend fleet `normal`/`warning`/`critical`/`offline` status and
`reporting_age_seconds` remain authoritative. The app does not compute a
second freshness threshold, infer device status from phone connectivity, or
turn network errors into tank outages. Water-quality alerts and monitoring
incidents remain separate. The Home API currently has no recent-activity
source, so the activity section is omitted for live data rather than filled
with demo actions.

Initial load has a Home-specific skeleton; full failure has a retry state;
secondary failures and failed refreshes preserve clear partial/stale labels.
Pull-to-refresh and resume refresh are supported; there is no periodic polling.
Live Home tank links pass the backend tank ID to the live M3 detail route. M4
Home alert references route into the live alert/monitoring stream.
`MockHomeRepository` remains available to the prototype and widget tests.

### M2 device smoke check

Install the latest release APK, sign in with an existing Railway account, and
check the Home fleet summary against the same account in the web dashboard.
Verify both Owner and Staff presentations, pull-to-refresh, and refresh after
backgrounding and reopening the app. With Home loaded, temporarily disconnect
the phone from the network and refresh: Home should show its API failure/stale
state without changing any tank's reported status. Restore the connection and
retry. Alerts and monitoring have live Railway-backed lists as of M4.

## M3 live Tanks integration

`ApiTankRepository` uses the M1 authenticated client. `GET /fleet` supplies the
directory in one request; search and All / Needs attention / Offline filters
are applied locally using the server's status. The app does not query each tank
for list cards and does not apply its own reporting-age threshold.

Opening a live tank requests `GET /tanks/{id}`,
`GET /tanks/{id}/operations`,
`GET /tanks/{id}/monitoring-incidents?state=active&page=1&page_size=100`, and
`GET /tanks/{id}/species-suitability` concurrently. Tank metadata is required;
supporting source failures are shown as unavailable while successful real data
is retained. Active water-quality alerts come from the operations snapshot;
monitoring incidents remain separate and only active incidents are shown.
M4 adds API-backed Alerts/Monitoring, resolved history, and alert
detail/handling, as described below.

Backend `normal`, `warning`, `critical`, and `offline` states and its
`reporting_age_seconds` / receipt-time evaluation remain authoritative. The
detail view shows temperature (°C), pH, turbidity (NTU), and TDS (ppm). Missing
values stay unavailable (never zero-filled), stale numeric values are labelled
last known, and `is_mock` provenance is retained when present. A phone/API
failure does not set a tank offline. The endpoint has no activity feed or
equipment-state payload, so those demo-only sections are hidden for live detail
rather than mixed with Railway data. Assigned species and suitability are
shown from their API payloads; live rows do not open demo species detail.

Directory/detail screens retain their existing design, repository seam, and
mock implementations. They provide first-load, retry, empty, pull-to-refresh,
stale-data, and resume refresh states; successful data is refreshed on resume
only when at least one minute old. There is no background polling.

### M3 device smoke check

Install the latest release APK, sign in with an existing Railway account, and
compare the Tanks directory/detail to the web dashboard. Check filters/search,
readings and units, assigned species, separate water-quality and monitoring
issues, and the offline label for a backend-reported outage. Verify that failed
phone networking reports an API problem without changing tank status. Retry
after restoring connectivity. Alerts were outside M3 and are covered by M4;
equipment state and activity remain outside the live slice.

## M4 live Alerts and Monitoring integration

`ApiAlertRepository` shares M1's authenticated `ApiClient` and maps backend DTOs
into the existing alert domain models. Active water-quality alerts use
`GET /alerts`; history uses `GET /alerts/history?resolved=true`. Alert responses
contain a tank ID but no tank display name, so the repository performs one
cached `GET /tanks?lifecycle=all` lookup to enrich records. If that lookup fails,
the alert remains usable with an explicit `Tank #id` label.

Monitoring active/history uses the paginated
`GET /monitoring-incidents?state=active|resolved&page=N&page_size=25` contract.
The list loads further pages on demand. Water-quality history and monitoring
history remain separate and are never combined into a single severity model.
Monitoring details show the backend lifecycle/reason and cannot be manually
resolved. Alert details are opened from the fetched list record; the backend
does not expose a separate single-alert detail route.

Water alert `warning`/`critical`, numeric IDs, nullable reading/resolution
fields, UTC timestamps, `operator`/`system` resolution sources, and monitoring
resolution reasons are parsed in DTO/mapping code. Local display dates are
converted from parsed timestamps; backend alert and monitoring state remains
authoritative. Mark handled is labeled as operator acknowledgement only: it
removes an alert from the active queue but does not confirm water recovery.
Automatically resolved alerts remain distinct from operator-handled alerts.

After confirmation, Mark handled sends bodyless `PUT /alerts/{id}/resolve` once.
The backend route is idempotent. If a timeout, network failure, or server error
makes the result ambiguous, the mobile client fetches current alert state to
reconcile; it does not blindly repeat the mutation. Permission and validation
errors are surfaced as safe app-level messages.

Water alerts and monitoring have independent loading, empty, retry, partial
source-error, pull-to-refresh, and stale-on-refresh states. Alerts refresh on
resume when the last success is at least one minute old and do not poll in the
background. Monitoring history is paginated; initial/reference loads follow
pages only when needed to find the requested incident. Tank Detail and Home
alert references pass backend IDs into these same live records. Network failure
is shown as unavailable API data and does not create a tank-offline state or a
monitoring incident. Tank Detail issue links work from both Home and Tanks.
Alert detail remains open after a confirmed Mark handled action and shows the
backend lifecycle/source and resolution time. Returning to Home or Alerts
refreshes the loaded view, and failed deep-link loads remain retryable rather
than being reported as missing records.

`MockAlertRepository` remains injectable for widget and repository tests. No
equipment or actuator command, push notification, or profile-edit API is part
of M4.

### M4 device smoke check

Install the release APK and sign in with an existing Railway account. Compare
active water alerts and monitoring incidents with the web dashboard, switch
between Active and History, open details from both Alerts and Tank Detail, and
pull to refresh. Background and resume the app after a minute to verify refresh.
Exercise Mark handled only with an appropriate test alert; confirm it leaves the
active queue while the detail wording does not claim water recovery. Confirm a
system-resolved alert is labeled as automatic and monitoring recovery remains
in Monitoring history. No physical equipment command is enabled by this
milestone.

## M5 Account identity, Species, and read-only Equipment

The More/Account card uses the authenticated user already restored through
`/auth/me`: backend name, email, role, and active status. `admin` is presented
as Owner and `staff` as Staff, without changing the backend role. The backend
does not expose a separate profile-edit route or an organization/customer
display field on `/auth/me`, so mobile does not submit profile changes or claim
that an organization label came from the server.

`ApiFishRepository` uses authenticated `GET /fish` and `GET /fish/{id}`. It
maps the backend's numeric IDs, snake_case care fields, category, nullable
preferred water ranges, diet, description, care tips, and compatibility notes
into the existing species model. Missing ranges and notes stay explicitly
unspecified. Backend category is not freshwater/saltwater: the live directory
suppresses those mock-only filters and shows category instead. Tank Detail
opens the live species record using its backend ID and retains the existing
tank assignment/suitability context. The current model does not display
`photo_url`, `tank_count`, or the full `assigned_tanks` list.

`ApiEquipmentRepository` is read-only. Owner/admin requests use `GET /devices`
to find registered devices for the selected tank, then call
`GET /tanks/{id}/actuators/status?device_id=...` and
`GET /tanks/{id}/actuators/history?device_id=...&page=1&page_size=10`. Explicit
device selection handles tanks with multiple registered devices. The screen
shows the five known actuator states, schedules where supplied, device
connectivity, last-reported timestamps, and the newest ten command lifecycle
records. Additional history pages are not yet exposed. Backend `succeeded`
means the lifecycle reported success, not physical verification; `outcome_unknown`
stays explicitly uncertain. These GET routes can reconcile overdue command
lifecycle records server-side, but the mobile client issues no physical command
and exposes no equipment mutation.

The backend restricts equipment state/history to `admin`. A live Staff screen
explains that restriction and makes no request; the app does not equate its
Staff read-only presentation with permission to call an admin-only endpoint.
Species remains staff/admin readable. Mock repositories remain injectable for
tests and local prototype flows. Species/equipment screens provide loading,
empty, retry, stale-data, pull-to-refresh, and one-minute resume refresh states;
they do not poll in the background.

### M5 device smoke check

Install the release APK and sign in with an existing Railway admin account.
Open More/Account and verify name, email, Owner role, and account status against
the signed-in backend identity. Open Fish species and compare names/categories
and available care fields with the web directory; open a species from Tank
Detail and confirm the assigned-tank/suitability context remains intact. Open
Equipment from a live tank and verify device state and recent command history.
Confirm that the screen says it is read-only and offers no physical controls.
If testing Staff, confirm the restriction explanation appears without issuing
device-state requests. Do not use actuator commands during this milestone.

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

The mock repositories `MockTankRepository`, `MockAlertRepository`,
`MockFishRepository`, and `MockEquipmentRepository` remain available for
deterministic tests and unsupported feature paths. They coexist with the live
API repositories and do not replace or redefine the FastAPI contract.

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

## M6.1 FCM client foundation

`FirebasePushNotificationService` is the single Flutter boundary for FCM.
Production composition initializes Firebase asynchronously so an unavailable
Firebase/FCM service cannot delay or crash the authentication flow. Tests inject
a fake service/platform and do not invoke Firebase plugins or Railway.

The service requests notification permission once during its initialization,
records authorized/denied/provisional/unavailable state, obtains the FCM token
into memory, and emits token refreshes. Debug output reports only a masked token
and its length. Foreground notification messages are displayed once through
`flutter_local_notifications`; Android handles notification messages normally
while backgrounded or terminated. Firebase and local-notification taps are
exposed as raw open events; M6.1 does not navigate from them.

Android uses the idempotent `aqualogic_alerts` / “AquaLogic Alerts” high-
importance channel and monochrome notification icon. Android 13+ requests
`POST_NOTIFICATIONS` at runtime; older Android releases do not need that runtime
permission. Denial does not gate login or app use.

### M6.1 manual device test

1. Install and launch the release APK on the Android phone. On Android 13+,
   allow notifications when prompted. Android 12 and older will not show that
   runtime prompt.
2. For token confirmation during development, run the debug app and verify the
   terminal reports an authorized/denied permission state and “FCM token
   obtained” with a masked value. Never share the complete token in chat or
   screenshots.
3. If Firebase Console requires the full token for a test send, pause the local
   Flutter debugger in `FirebasePushNotificationService._setToken` and copy the
   `token` variable directly from the debugger into the Console. Do not print it
   or save it in the repository.
4. In Firebase Console, open **DevOps & Engagement > Messaging**, create a
   Firebase Notification campaign, enter a title/body, and choose **Send test
   message** from the right pane. Enter the token in **Add an FCM registration
   token** and select **Test**. Verify: foreground shows one local notification;
   background and terminated states show Android's FCM notification; tapping a
   notification launches/resumes AquaLogic and is captured internally without
   navigation. For the terminated-state check, swipe the app away from Recents;
   Android suppresses FCM delivery after a Force stop until the app is opened
   manually. See the [official Android test-message steps](https://firebase.google.com/docs/cloud-messaging/android/get-started) and [Flutter receive-message guidance](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages).
5. Do not send production alert content; M6.1 does not register tokens with
   Railway or trigger alert/monitoring sends.

The physical Android 12 check on 2026-09-26 reported authorized notification
access and obtained a 142-character token in masked debug output. The Firebase
Console lifecycle test remains for the developer to run manually.

## M6.2 Authenticated device registration

Production composition starts one registration coordinator alongside the M6.1
FCM service and API auth service. It registers only after auth restore/login has
established a completed `admin` or `staff` session and either an FID or a legacy
FCM token is available. Registration errors are contained and retried with
bounded backoff; they do not change authentication state or block app startup.

The client creates one random UUID per app installation, stores it in Android
secure storage, and never reads hardware identifiers. Android enables Firebase
Messaging's FID registration mode and awaits native
`FirebaseMessaging.register()` before FlutterFire reads the FID through
`FirebaseInstallations.instance.getId()`. It listens to the supported
`onIdChange` stream and repeats registration before publishing a changed FID.
The authenticated request sends the local UUID, separate FID, Android platform,
and `firebase_installation_id_registered: true`; Android does not call the
legacy FCM token getter in FID mode. The request still supports an optional
distinct FCM token for older clients. The backend derives both user and
`AuthSession` from the validated access JWT. FID or token refresh updates the
existing installation; signing into another account rebinds it. Responses and
application logs contain neither Firebase identifier. Normal logout attempts
`DELETE /push/devices/current/{installation_id}` before revoking the backend
session; logout proceeds if this request fails.

Migration `0015_authenticated_push_devices` adds session-bound registrations.
Migration `0017_push_device_firebase_installation_id` adds a nullable unique
FID column without editing `0015` or removing the existing production row.
Migration `0018_push_device_fid_registration` distinguishes an FID fetched by
the app from one registered with FCM and permits FID-only requests. Pre-existing
rows stay on the retained-token compatibility path until the current app
confirms FID registration. The sender targets `messaging.Message(fid=...)` only
when that marker is true; otherwise it uses the retained FCM token. The backend
eligibility query continues to exclude inactive devices/accounts, unsupported
roles, and expired or revoked sessions even when deactivation did not reach the
server. API responses omit both Firebase identifiers.

## M6.3 Firebase Admin sender and outbox

The backend has an optional Firebase Admin sender, versioned string-only
payloads, a transactional notification-event enqueue helper, and per-device
delivery records. The dispatcher runs independently from sensor and actuator
maintenance, claims work with a database lease, rechecks user/session/device
eligibility immediately before sending, and retries transient failures with a
bounded backoff. The sender uses `messaging.Message(fid=...)` only for rows
whose explicit FCM-registration marker is true and falls back to the retained
FCM token for compatibility. An unregistered recipient deactivates only the
matching current identifier.
Global credential errors keep deliveries retryable and never deactivate
devices. No alert or monitoring source code enqueues these events yet; those
triggers remain M6.5. A missing or invalid global credential is logged without
exception detail, leaves deliveries retryable, and pauses that process's
dispatcher until Railway restarts with corrected configuration.

`PUSH_NOTIFICATIONS_ENABLED` defaults to false. Firebase credentials belong in
Railway's `FIREBASE_SERVICE_ACCOUNT_JSON_B64` secret, never in the repository,
Flutter, or `google-services.json`. Credential provisioning was handled
directly in Railway and is not represented in source control. The first
controlled production test was rejected as an unregistered recipient, which
showed that storing an FID alone did not prove FCM had registered it. The
corrected Android registration and migration `0018` are in progress. M6.4
remains gated on an updated physical Android installation registering its FID,
one successful controlled test, and human receipt confirmation. See the
[Firebase Admin setup checkpoint](../WORKFLOWS.md#firebase-admin-push-setup).

## Remaining work after M6.2 registration

The following remain outside the completed M5 integration:

- Profile editing and organization/customer profile display, which need a
  defined backend contract before mobile can expose them.
- Older equipment command-history pages, if an operational need is confirmed.
- A backend recent-activity source and historical sensor readings/charts.
- Real actuator commands and production equipment safety controls remain
  disabled in Flutter.
- The M6.3 FID-registration correction and authenticated physical re-registration
  gates must pass before M6.4; physical test push, event triggers, and
  notification tap navigation are the later M6.4–M6.6 gates. M6.1 provides the client-side
  Firebase initialization, permission, token lifecycle, foreground display,
  background handler registration, and open-event capture; M6.2 provides
  authenticated device registration, extended with FIDs in M6.3.

Mock repositories remain available for deterministic tests and features without
live API support. Production composition uses API repositories for
Authentication, Home, Tanks, Alerts, Monitoring, Species, and read-only
Equipment.

## Important locations

- `mobile_app/lib/app/`: app composition, theme, navigation, and startup.
- `mobile_app/lib/app/auth/`: auth scope and the startup authentication gate.
- `mobile_app/lib/features/auth/`: API and mock auth services, secure refresh
  storage, user and role models, forced password-change gate, and login screen.
- `mobile_app/lib/features/home/`: role-aware Home compositions, mock and API
  repositories, wire DTO mapping, local Home presentation models, and shared
  Home widgets.
- `mobile_app/lib/features/tanks/`: tank directory/detail, shared DTO parsing,
  mock and API repositories, readings, issues, and lifecycle.
- `mobile_app/lib/features/alerts/`: water-quality and monitoring alert models,
  DTO/API and mock repositories, list/detail views, and safe handling
  reconciliation.
- `mobile_app/lib/features/fish/`: species directory, detail, suitability, and
  mock and API fish repositories, DTO mapping, and suitability context.
- `mobile_app/lib/features/control/`: contextual Equipment models, mock
  and read-only API repositories, command lifecycle, and Owner/Staff equipment
  view.
- `mobile_app/lib/features/more/`: account, local-data, and about surfaces.
- `mobile_app/lib/features/push_notifications/`: FCM service boundary, Android
  Firebase/local-notification adapter, payload events, token lifecycle, and
  focused fake-platform tests.
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

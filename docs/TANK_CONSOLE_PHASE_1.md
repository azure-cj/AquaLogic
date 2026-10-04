# Tank Console Mode — Phase 1

Status: Current UI prototype; hardware integration deferred
Last reviewed: 2026-10-04

## Scope and entry

The existing Flutter APK includes **More → Tank Console → Enter Console Mode**.
The exhibit interface uses a dark landscape dashboard with tank identity, four
large readings, water-quality interpretation, lighting/UV/feeder controls,
read-only Pump A/B placeholders, and independent Local/Cloud indicators.
Every prototype screen labels its data **Prototype · simulated data**.

No firmware, gateway, backend, Railway API, ESP32 HTTP, discovery, pairing,
authentication, or synchronization has been added by this feature. Existing
Railway repositories remain separate. No dosing command exists in the console
contract. The reference illustration supplies visual direction; its water-change
and fish-information controls are outside this phase's approved scope.

## Feature architecture

- [`console/`](../mobile_app/lib/features/console/) owns its models, repository
  contract, controller, screens, widgets, and display adapter.
- [`ConsoleState`](../mobile_app/lib/features/console/models/console_state.dart)
  contains readings, connection flags, equipment state and latest command.
  `getEquipmentState()` reads that same equipment snapshot.
- [`ConsoleRepository`](../mobile_app/lib/features/console/data/console_repository.dart)
  exposes typed command IDs/results and state/command streams. The controller
  and widgets consume this abstraction rather than networking or mock classes.
- [`MockConsoleRepository`](../mobile_app/lib/features/console/data/mock_console_repository.dart)
  holds deterministic fixtures and simulated execution. Readings do not jump
  randomly. Default values are 27.3 °C, pH 7.32, 124 ppm and 4.8 NTU.
- [`Esp32ConsoleRepository`](../mobile_app/lib/features/console/data/esp32_console_repository.dart)
  is an unavailable placeholder. It performs no networking and is never selected
  by normal app composition.
- [`ConsoleRepositoryScope`](../mobile_app/lib/app/console/console_repository_scope.dart)
  injects a repository factory into the More entry. Each console session owns
  a fresh repository; route rebuilds do not create extra instances.

## Interactions and uncertainty

Light, UV and feeder submissions return a typed `ConsoleCommand`. Default mock
progress is ACCEPTED → RUNNING (450 ms) → COMPLETED (1700 ms). Equipment changes
are confirmed on completion; feeder displays RUNNING during execution. IDLE,
REJECTED and UNKNOWN are represented explicitly. Duplicate/concurrent commands
are rejected and cannot replace the active operation. Mock history is bounded.

Cloud unavailable does not disable local commands. Local unavailable rejects
commands and the UI displays cached readings with their last observation time.
Retry restores only the simulated Local connection and does not replay commands
or restore Cloud. Scenario changes during execution make the outcome UNKNOWN;
delayed callbacks cannot subsequently manufacture completion.

Uncertainty remains in the affected equipment snapshot even after an unrelated
command. That equipment cannot accept another command until a fresh confirmed
report. For the prototype, selecting **Normal** while no command is pending
simulates that report. Retrying a connection alone does not confirm equipment.
Pumps have information sheets only, with no simulated dispense action.

Settings expose deterministic Normal, Attention, Critical, Local offline, Cloud
offline, Both offline, next Rejected and next UNKNOWN scenarios. These optional
prototype controls are separate from the future production repository contract.
Water-quality fixtures are demonstration states, not new real quality rules.

## Display and notification boundaries

The Android activity's separate console display channel saves prior orientation,
system-bar visibility/behavior and keep-awake flag, enters sensor landscape and
immersive display, and restores saved settings on exit/disposal. Calls are
serialized; restoration is idempotent. Resume reapplies immersive display only
while the console session is active. No kiosk/device-lockdown is implemented.

Back and settings exit require an explicit exit confirmation. Short landscape
screens and enlarged text receive a scroll fallback rather than clipped content.
Normal phone landscape sizes retain the four-metric/five-equipment layout.

Notification registration, delivery and authentication remain unchanged.
Notification navigation is suspended only during the active console route.
The existing single pending-tap slot is retained; navigation resumes after exit.
This does not introduce a new push queue or alter normal app navigation.

## Validation and device review

### Files changed for this feature

New files under `mobile_app/`:

- `lib/app/console/console_repository_scope.dart`
- `lib/features/console/models/console_state.dart`
- `lib/features/console/models/console_command.dart`
- `lib/features/console/data/console_repository.dart`
- `lib/features/console/data/mock_console_repository.dart`
- `lib/features/console/data/esp32_console_repository.dart`
- `lib/features/console/controllers/console_controller.dart`
- `lib/features/console/platform/console_display_session.dart`
- `lib/features/console/screens/console_entry_screen.dart`
- `lib/features/console/screens/tank_console_screen.dart`
- `lib/features/console/widgets/console_style.dart`
- `lib/features/console/widgets/console_metric_card.dart`
- `lib/features/console/widgets/console_equipment_card.dart`
- `lib/features/console/widgets/console_connection_indicator.dart`
- `lib/features/console/widgets/console_status_bar.dart`
- `lib/features/console/widgets/console_warning_card.dart`
- `lib/features/console/widgets/console_command_sheet.dart`
- `lib/features/console/widgets/console_settings_sheet.dart`
- `test/console_mode_test.dart`

Existing mobile files edited:

- `lib/app/aqualogic_app.dart`: isolated repository factory and console push guard.
- `lib/features/more/screens/more_screen.dart`: additive console entry.
- `lib/features/push_notifications/data/notification_navigation_coordinator.dart`:
  suspend/resume navigation during the console session.
- `android/app/src/main/kotlin/com/aqualogic/aqualogic/MainActivity.kt`:
  separate display-session channel; existing Firebase registration channel kept.
- `test/notification_navigation_coordinator_test.dart`: deferred-tap coverage.
- `test/mobile_refinement_test.dart`: scroll to About in the longer More list.

Documentation: this new report plus `docs/INDEX.md`, `docs/areas/MOBILE.md`,
`docs/DEVELOPMENT_STATUS.md` and `docs/DECISIONS.md`. Pre-existing uncommitted
work elsewhere in the workspace was preserved; it is not part of this feature.

### Automated checks

Final verification on 2026-10-04:

- Dart formatting completed for all feature and integration files.
- `flutter analyze`: no issues found.
- Full `flutter test`: **221 tests passed**, including the 15 focused console
  tests and notification suspension coverage.
- Four optional landscape render captures passed and were visually inspected
  for Normal, Attention, Cloud unavailable and Local offline.
- `flutter build apk --release`: succeeded, producing
  `mobile_app/build/app/outputs/flutter-apk/app-release.apk` (61.0 MB).
- `git diff --check`: passed. Build output and preview images remain ignored.

The release build emits a Firebase plugin/Kotlin Gradle migration warning for
`firebase_app_installations` and `firebase_core`; it did not prevent this build.
Android behavior has not been validated on a physical device during this task.

Focused tests live in
[`console_mode_test.dart`](../mobile_app/test/console_mode_test.dart) and
[`notification_navigation_coordinator_test.dart`](../mobile_app/test/notification_navigation_coordinator_test.dart).
Coverage includes command transitions, no optimistic equipment changes, duplicate
submissions, connection independence, disconnect during execution, uncertainty,
read-only pumps, More entry/guarded exit, four viewport sizes, enlarged text and
notification navigation deferral. The existing More destination test scrolls to
About now that the list includes the new entry.

From `mobile_app`, run formatting, `flutter analyze`, `flutter test`, and
`flutter build apk --release`. Optional preview captures use
`CONSOLE_CAPTURE=1 flutter test test/console_mode_test.dart --plain-name capture`
and write ignored images under `build/console-preview/`. Capture tests load the
real Geist and Material icon fonts; these are render evidence, not device tests.

Before mounting the phone, verify on the intended Android device:

1. Enter/exit from portrait and both landscape orientations; prior orientation
   and system bars return correctly after exit, including repeated sessions.
2. Screen stays awake during console use and returns to its previous sleep
   behavior after exit; background/resume preserves console mode.
3. Display cutouts, gesture navigation, large text, touch targets and readings
   remain usable at approximately one meter.
4. Feed/lighting/UV confirmations, progress, offline/retry, UNKNOWN and pump
   information behave as described, without controlling physical hardware.
5. Receive/tap a push while in console; it stays mounted, and deferred navigation
   follows the existing authentication checks after deliberate exit.
6. Normal Home, Tanks, Alerts, More, authentication and push flows still work.

Actual local control, ESP32 safety enforcement, authoritative hardware feedback,
pairing, saved startup preference and cloud event history are Phase 2 work and
require the firmware audit/safety review before implementation.

# Tank Console Phase 2A — local read-only monitor

Implemented 2026-10-06. Physical Android/ESP32 verification remains pending.

The subsequent [integration-readiness pass](TANK_CONSOLE_INTEGRATION_READINESS.md)
adds full contract fixtures, portable real HTTP tests, safer socket cleanup,
distinct connection messages and collaborator setup. Its verification supersedes
the original Phase 2A counts below.

## Composition and setup

Production Android uses Esp32ConsoleRepository for More → Tank Console.
Mock-auth/browser previews and injected test factories retain simulation.
Console widgets consume ConsoleRepository, not HTTP. All live command methods
throw UnsupportedError and the controller/dashboard disable them independently.
Pumps show actual reported motion or Unknown; no pump commands exist.

Entry and Console settings share Save host / Test Connection. A dedicated
secure-storage key persists a private IPv4, LAN hostname or .local name,
without scheme, port, path or credentials. Names must resolve to private IPv4.
Changing host clears previous-device readings. Test Connection saves the host,
then verifies a received sensor reading and reports partial equipment failures.
Use a router DHCP reservation/private IP initially; Android name resolution
needs physical verification. No discovery, pairing or hardcoded IP was added.

The primary firmware source is the extensionless root file esp32, updated by
248c698, not an actual tracked .ino path. Confirm the flashed binary with the
collaborator. [Firmware contract](TANK_CONSOLE_FIRMWARE_CONTRACT.md) records all
42 routes, methods, exact JSON construction and Wi-Fi/schedule semantics.

## Polling, unavailable data and freshness

A repository-owned serial cycle issues six GETs: /data, /led/status,
/uv/status, /feeder/status, /syringeA/status, /syringeB/status. Start cadence is
roughly two seconds; slow cycles never overlap. Multiple listeners and retries
share the same in-flight cycle. Listener cancellation stops future timers;
owned repository disposal closes clients and prevents later emissions.
Requests have three-second connect/total deadlines, a 64 KiB response limit,
no redirects and no cloud credentials. Failed /data short-circuits the cycle.

Missing/null/malformed/non-finite sensors show unavailable, never zero. A real
zero remains zero; DallasTemperature's -127 disconnect sentinel is unavailable.
GOOD/MONITOR/CRITICAL maps existing firmware classifications only when all four
values are available. No new water thresholds were added. Equipment Booleans
must be actual JSON Booleans; missing reports show Unknown, never assumed idle.

Local states are connecting, connected, degraded and disconnected. Failed
updates retain last-known readings and immediately mark them stale/degraded.
After ten seconds without a successful receipt, local status is unavailable
and equipment becomes Unknown. Polling recovers automatically. Partial valid
responses show known fields and explicitly unavailable missing fields.
Receipt time is not sensor capture time: firmware /data has no sample timestamp,
validity flags or boot sequence, and cannot prove fresh physical sampling.
Firmware pH uses calculateDemoPH and turbidity is prototype-calibrated; physical
calibration remains a hardware gate, not a Flutter guarantee.

## Cloud, authentication and notifications

No firmware, backend, gateway, cloud repository or authentication behavior was
changed. The gateway remains the sole backlog acknowledger and uploads normally.
The Console only reads; firmware schedules remain authoritative.

The existing app has no reusable continuous cloud-health signal. Live Console
therefore displays **Cloud · Unknown** rather than inventing healthy/offline
cloud from Wi-Fi, authentication or ESP32 response. Local polling never calls
Railway or depends on Internet. Existing cloud screens retain their behavior.
Binding verified cloud health is a separate follow-up.

Normal authenticated entry is preserved. Phase 2A does not add an offline cold-
start launcher outside the auth shell: enter Console while signed in before
testing Internet loss. Local settings/polling themselves require no Internet.
Notification navigation remains suspended until exit. Display restoration is
unchanged; physical background/resume, orientation and awake checks remain.

## Android HTTP policy

Release retains usesCleartextTraffic=false and a native default policy denying
cleartext, with a narrow exception for firmware hostname aqualogic.local.
The debug resource preserves prior debug HTTP behavior. Flutter documents that
Dart-owned HttpClient sockets do not enforce native policy; configured dynamic
IP traffic therefore uses strict application checks: private address validation,
resolved-address pinning, six GET paths, no redirects/custom ports/public URLs.
Railway HTTPS/certificate handling stays unchanged. The earlier claim that the
manifest alone blocks Dart release HTTP was too strong; verify the release APK
on the actual phone.

References: [Flutter policy](https://docs.flutter.dev/release/breaking-changes/network-policy-ios-android),
[Android network-security configuration](https://developer.android.com/privacy-and-security/security-config).

## Phase 2B gates

Verify flashed firmware, protect unauthenticated mutation endpoints, define
command acknowledgement/outcome tracking and manual/schedule/gateway arbitration
before enabling LED/UV. Reported state is not physical relay feedback. Timeouts
must become UNKNOWN without automatic replay. Feeder fed:true can mean a busy
request was skipped. Pumps/test-dispense remain out of scope; test-dispense
bypasses chemical time/cooldown checks and needs protection before dosing.

## Physical checklist

1. Confirm flashed sketch identity with collaborator.
2. Put ESP32, mounted Android and gateway on the same Wi-Fi.
3. Install release APK; configure the actual private IP; Test Connection succeeds.
4. Compare four readings/statuses against /data and LED/UV/feeder/pump states.
5. Verify every live control remains unavailable, including pump panels.
6. Disconnect Internet while keeping Wi-Fi: local telemetry continues. Cloud
   remains Unknown until a verified signal exists; inspect cloud screens separately.
7. Disconnect/restart ESP32: readings remain last-known/stale, then unavailable
   after ten seconds; equipment becomes Unknown; controls remain disabled.
8. Restore ESP32: automatic recovery, without duplicate polling.
9. Confirm gateway uploads and backlog recovery still work.
10. Receive/tap a push during Console: no unsolicited navigation away.
11. Exit/reenter: saved host restored; orientation/system UI/awake state restored.
12. Test background/resume and actual probe calibration on the physical device.

## Verification

Formatting and git diff --check completed. Flutter analyze passed with no
issues. Focused Console/preview tests passed (39); the full Flutter suite passed
245 tests. Final Android release APK build succeeded (61.3 MB) at
mobile_app/build/app/outputs/flutter-apk/app-release.apk. Existing Firebase
plugins emitted a future Kotlin Gradle compatibility warning without failing
the build. Fixtures/build results do not certify a physical ESP32/Android device.


## Changed files

This milestone changes these 31 files; pre-existing untracked image/screenshot assets are untouched.

- [docs/DECISIONS.md](../docs/DECISIONS.md)
- [docs/DEVELOPMENT_STATUS.md](../docs/DEVELOPMENT_STATUS.md)
- [docs/INDEX.md](../docs/INDEX.md)
- [docs/TANK_CONSOLE_FIRMWARE_CONTRACT.md](../docs/TANK_CONSOLE_FIRMWARE_CONTRACT.md)
- [docs/TANK_CONSOLE_PHASE_2A.md](../docs/TANK_CONSOLE_PHASE_2A.md)
- [mobile_app/android/.gitignore](../mobile_app/android/.gitignore)
- [mobile_app/android/app/src/debug/res/xml/network_security_config.xml](../mobile_app/android/app/src/debug/res/xml/network_security_config.xml)
- [mobile_app/android/app/src/main/AndroidManifest.xml](../mobile_app/android/app/src/main/AndroidManifest.xml)
- [mobile_app/android/app/src/main/res/xml/network_security_config.xml](../mobile_app/android/app/src/main/res/xml/network_security_config.xml)
- [mobile_app/lib/app/aqualogic_app.dart](../mobile_app/lib/app/aqualogic_app.dart)
- [mobile_app/lib/app/console/console_repository_scope.dart](../mobile_app/lib/app/console/console_repository_scope.dart)
- [mobile_app/lib/features/console/controllers/console_controller.dart](../mobile_app/lib/features/console/controllers/console_controller.dart)
- [mobile_app/lib/features/console/data/console_configuration_store.dart](../mobile_app/lib/features/console/data/console_configuration_store.dart)
- [mobile_app/lib/features/console/data/console_http_transport.dart](../mobile_app/lib/features/console/data/console_http_transport.dart)
- [mobile_app/lib/features/console/data/console_http_transport_io.dart](../mobile_app/lib/features/console/data/console_http_transport_io.dart)
- [mobile_app/lib/features/console/data/console_http_transport_stub.dart](../mobile_app/lib/features/console/data/console_http_transport_stub.dart)
- [mobile_app/lib/features/console/data/console_repository.dart](../mobile_app/lib/features/console/data/console_repository.dart)
- [mobile_app/lib/features/console/data/esp32_console_parser.dart](../mobile_app/lib/features/console/data/esp32_console_parser.dart)
- [mobile_app/lib/features/console/data/esp32_console_repository.dart](../mobile_app/lib/features/console/data/esp32_console_repository.dart)
- [mobile_app/lib/features/console/models/console_state.dart](../mobile_app/lib/features/console/models/console_state.dart)
- [mobile_app/lib/features/console/screens/console_entry_screen.dart](../mobile_app/lib/features/console/screens/console_entry_screen.dart)
- [mobile_app/lib/features/console/screens/tank_console_screen.dart](../mobile_app/lib/features/console/screens/tank_console_screen.dart)
- [mobile_app/lib/features/console/widgets/console_command_sheet.dart](../mobile_app/lib/features/console/widgets/console_command_sheet.dart)
- [mobile_app/lib/features/console/widgets/console_connection_indicator.dart](../mobile_app/lib/features/console/widgets/console_connection_indicator.dart)
- [mobile_app/lib/features/console/widgets/console_endpoint_settings.dart](../mobile_app/lib/features/console/widgets/console_endpoint_settings.dart)
- [mobile_app/lib/features/console/widgets/console_metric_card.dart](../mobile_app/lib/features/console/widgets/console_metric_card.dart)
- [mobile_app/lib/features/console/widgets/console_settings_sheet.dart](../mobile_app/lib/features/console/widgets/console_settings_sheet.dart)
- [mobile_app/lib/features/console/widgets/console_warning_card.dart](../mobile_app/lib/features/console/widgets/console_warning_card.dart)
- [mobile_app/lib/features/more/screens/more_screen.dart](../mobile_app/lib/features/more/screens/more_screen.dart)
- [mobile_app/test/console_mode_test.dart](../mobile_app/test/console_mode_test.dart)
- [mobile_app/test/esp32_console_test.dart](../mobile_app/test/esp32_console_test.dart)

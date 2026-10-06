# Tank Console integration readiness

Historical read-only checkpoint. [Phase 2B](TANK_CONSOLE_PHASE_2B.md) supersedes
the command-disabled boundary; transport/readiness protections remain.
Physical local connectivity was subsequently confirmed by the owner.

Software-side hardening, 2026-10-06. All real actuator commands stay disabled.
The external contract is root `esp32` at `248c698` (blob
`df25c0b22407b303ed410b1d975b0e5c0da92a20`). The working source matches that
blob. Firmware, bridge, gateway, backend and web are unchanged.

## Collaborator setup

Install the release APK and sign in normally beforehand. Then:

1. Connect Android and ESP32 to the same Wi-Fi.
2. Determine the ESP32 IP from the router or its serial output.
3. Open More → Tank Console and enter that IP (host only, no `http://`).
4. Press **Test Connection**.
5. Open **Enter Console Mode**.

Expect four sensor readings and LED, UV, feeder and both pump statuses.
Equipment is read-only, including when Local is connected. Cloud is **Unknown**
until a separate verified cloud-health signal is available. Local polling does
not call Railway or require Internet. Normal authenticated entry is retained;
this milestone does not add an offline cold-start launcher.

`aqualogic.local` is the source firmware's mDNS name; resolution depends on the
phone/network. A router-reserved private IPv4 address is the reliable baseline.
There is no hardcoded exhibit IP, pairing or automatic discovery.

## Setup messages

| Result | Guidance |
| --- | --- |
| Malformed host | Enter a private IPv4/local host without URL, path, port or credentials. |
| Unreachable | Confirm address and shared Wi-Fi; try the IP if hostname lookup fails. |
| Timeout | Check shared Wi-Fi/address and test again; no command is retried. |
| HTTP error | Confirm address and expected AquaLogic firmware. |
| Invalid/empty response | Device responded but did not provide usable sensor data; confirm firmware/address. |
| Partial | Sensor data is reachable but some readings/status endpoints are unavailable. |
| Verified | Local telemetry and equipment status are reachable; controls stay disabled. |

If setup fails, open `http://<ESP32 IP>/data` in the phone browser and compare
the response with the [firmware contract](TANK_CONSOLE_FIRMWARE_CONTRACT.md).
If the browser also fails, check ESP32 power/IP, router client isolation,
guest networks and VPN routing. If the browser works but the app does not,
record the app message, Android version and the six status responses for review.
Do not send Wi-Fi passwords or cloud tokens.

## Tests without hardware

[Fixtures](../mobile_app/test/fixtures/esp32_248c698/responses.json) contain
all fields emitted by the six read handlers, including UV's unusual `led_on`,
three schedule entries, pump volume/time fields and actual JSON types. Values
are synthetic; failures are explicit fixture mutations, not new firmware APIs.

[Network tests](../mobile_app/test/esp32_console_network_test.dart) use actual
Dart HttpClient requests and real sockets against an ephemeral loopback server.
A test-only socket factory redirects the validated private test address to
that server. No production exception for loopback, custom ports or arbitrary
paths was added. The tests run in the normal suite with no hardware/LAN setup.
They cover transport → repository → parser → controller and a landscape Console
widget, including rebuild and exit. A separate earlier private-LAN/port-80
simulation also passed, before the portable fixture suite was added.

Verified scenarios include full responses, missing/null/extra fields, broken
JSON, empty objects, HTTP errors, refused sockets, three-second deadlines,
slow serial cycles, disappearing/reappearing server, one failed pump endpoint,
last-known/stale retention, automatic recovery and independent Unknown Cloud.
The default two-second cadence, shared retries/subscriptions, repeated start,
stop/re-entry, host changes and disposal are exercised. UI tests cover distinct
connection messages; existing host validation and secure-storage tests remain.

Security checks cover six GET paths only, private destinations, rejected ports,
schemes, credentials, queries/fragments, public/loopback addresses, redirects and
oversized bodies. Server assertions verify no Authorization or Cookie headers.
Live command methods fail before any request. Android network policy was not
broadened during this readiness pass.

## Fixes from this audit

- Safe, distinct connection guidance replaces generic failures; no stack traces.
- Transport disposal closes a snapshot of active clients, preventing concurrent
  collection modification when a pending socket completes during shutdown.
- Returning from Console reloads the setup editor, so an address changed inside
  Console settings cannot later be overwritten by stale entry-screen text.
- Fixture/socket tests are portable rather than requiring an opt-in LAN server.

## Changed files in this readiness pass

- `mobile_app/lib/features/console/data/console_http_transport.dart`
- `mobile_app/lib/features/console/data/console_http_transport_io.dart`
- `mobile_app/lib/features/console/data/esp32_console_repository.dart`
- `mobile_app/lib/features/console/widgets/console_endpoint_settings.dart`
- `mobile_app/lib/features/console/screens/console_entry_screen.dart`
- `mobile_app/test/esp32_console_test.dart`
- `mobile_app/test/esp32_console_network_test.dart`
- `mobile_app/test/fixtures/esp32_248c698/responses.json`
- `mobile_app/test/fixtures/esp32_248c698/README.md`
- This document, documentation index, mobile area guide and Phase 2A/status notes.

This includes the earlier Phase 2A changes. Unrelated existing assets remain
untouched. Validation below was recorded before the user's subsequent commit
request; no push is part of this handoff.

## Physical assumptions still requiring confirmation

The collaborator must confirm the flashed sketch matches `248c698`; Git cannot
prove the binary. Confirm release APK installation, local Wi-Fi routing, actual
hostname resolution, probe calibration, reported equipment behavior and response
timing while firmware schedules/gateway are active. Firmware `/data` has no
sample timestamp or validity flags; HTTP receipt does not certify sensor health.
Equipment state is firmware-reported motion/state, not verified relay feedback.

On the mounted phone, test Internet loss with Wi-Fi retained, ESP32 restart and
automatic recovery, gateway uploads, push-navigation suspension, background/
resume, screen awake behavior and orientation/system-UI restoration on exit.
Unauthenticated firmware mutation routes and command acknowledgement/arbitration
remain Phase 2B gates. This readiness pass does not change or approve them.

## Final software verification

- Formatting and `git diff --check`: passed.
- `flutter analyze`: no issues.
- Focused Console/preview suite: 57 passed (18 added during readiness: 15 real
  socket tests and 3 additional setup-error UI cases).
- Full Flutter suite: 263 passed.
- The strengthened new-widget rebuild test was also rerun independently: passed.
- Direct source/fixture audit: all emitted JSON keys represented for six routes.
- `flutter build apk --release`: succeeded, 61.3 MB. Existing Firebase/Kotlin
  plugin compatibility warnings are non-blocking; dependencies were not changed.
- APK: `mobile_app/build/app/outputs/flutter-apk/app-release.apk`.
- SHA-256: `C91F8BFCBAD4867EC63E052819547E8FE8FDA00B8E35CBA28EB143A7E68625AD`.
- Validation base: `main`, HEAD `7942219`, with Phase 2A and readiness changes
  pending commit at verification time. Excluded application directories unchanged.

This verifies the software integration path against simulated contract responses,
not the physical hardware or Android release network stack.

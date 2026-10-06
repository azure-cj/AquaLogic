# Tank Console Phase 2B — live local controls

Last reviewed: 2026-10-07. Local `main` implementation, validated before the
owner's subsequent local commit request. No push is part of this milestone.
The owner reports that physical read-only connectivity passed before this phase.
New actuator behavior still requires physical validation.

## Exact immutable contract

Reference: extensionless root `esp32`, commit `248c698`, blob
`df25c0b22407b303ed410b1d975b0e5c0da92a20`. Source is unchanged.
See [the complete firmware contract](TANK_CONSOLE_FIRMWARE_CONTRACT.md).
Git does not prove which binary is flashed. Routes below register HTTP_ANY;
Console uses **GET only**, as the firmware dashboard does, with no parameters.

| Operation | Route(s) | Exact HTTP 200 body | Confirmation evidence |
|---|---|---|---|
| LED ON/OFF | `/led/on`, `/led/off` | `{"led":"on"}`, `{"led":"off"}` | Fresh `/led/status` field `led_on` matches requested state. |
| UV ON/OFF | `/uv/on`, `/uv/off` | `{"led":"on"}`, `{"led":"off"}` | Fresh `/uv/status` field `led_on` matches; completely separate LED/UV domain values. |
| Feed once | `/feeder/feed` | `{"fed":true}` | New `feed_count` relative to baseline, then `feeding:false`. |
| A/B dispense | `/syringeA/dispense`, `/syringeB/dispense` | `{"dispensed":true}` | New `dose_count`, then `active:false`. |
| A/B stop | `/syringeA/stop`, `/syringeB/stop` | `{"stopped":true}` | Fresh `active:false`; delivered amount remains unverified. |
| A/B full retract | `/syringeA/retract`, `/syringeB/retract` | `{"retracted":true}` | Observe `active:true`, then `active:false`; missed active interval leaves UNKNOWN. |
| A/B refill confirmation | `/syringeA/refill-confirm`, `/syringeB/refill-confirm` | `{"refill_confirmed":true}` | Recognized acknowledgement plus `volume_known:true`, remaining volume equal to capacity. |

Dispense refusal: HTTP 409,
`{"dispensed":false,"reason":"firmware text","next_eligible_at":"firmware time"}`.
Refill refusal: HTTP 409 (busy/persistent state unavailable) or 503 (save failure),
`{"refill_confirmed":false,"reason":"firmware text"}`. Console preserves the
bounded firmware reason. Generic HTTP failures and malformed acknowledgements
do not establish a refusal or success and become UNKNOWN.

Also present, deliberately excluded: `/syringeA/test-dispense` and
`/syringeB/test-dispense`, pump schedule routes, LED/UV timers/schedules, feeder
test/config/schedule, pH auto/demo, Wi-Fi and backlog routes. Test-dispense returns
200 `{"dispensed":true}` or 409 `{"dispensed":false,"reason":"firmware text"}`,
but bypasses chemical-dose time/cooldown checks. No HTTP dose-volume setter exists.
The Console never invokes test-dispense, edits scheduling or supplies volume.

## Firmware safeguards and known defects

Normal dispense calls `triggerSyringe*(true)`: checks persistent safety state,
known syringe contents, sufficient estimated remaining liquid, both motors idle,
synchronized Asia/Manila time and shared two-hour chemical-dose cooldown. It
reserves liquid/cooldown and persists before loop services the motor. Persistence
failure rolls back and rejects. Source defaults: 1 mL dose, 5 mL capacity;
persisted positive doses up to capacity may be restored. Console validates finite,
positive reported dose within reported capacity (at most 5 mL); it requests no
arbitrary volume. Firmware remains authoritative for final permission.

Refill confirmation follows a physical refill/check. It updates the volume
estimate without moving a motor or clearing cooldown. Retract is a supervised
full-capacity reverse stroke with mutual exclusion; it does not confirm liquid
volume or clear cooldown. Stop does not refund reserved volume/reset cooldown.
Maintenance never calls the weaker test-dispense path.

Unchanged acknowledgement defects: `fed:true` and `retracted:true` are also sent
when busy guards skip their operations. Feed/dose counters increment at START,
not physical completion. There are no command IDs or food/liquid delivery sensors.
A counter increase followed by idle confirms observed firmware activity, **not
physical delivery or attribution to this particular local request**. Another
gateway or schedule operation may account for it. UI messages explicitly retain
that distinction. A short retract can miss the active observation and stay
UNKNOWN; recovered idle alone cannot prove it ran. No firmware fixes were made.

LED ON/OFF sets firmware manual override; schedule-window changes clear it.
UV ON/OFF clears timer duration; enabled UV scheduling can reassert its state.
Every poll follows actual reports. Console adds no permanent override/arbitration.

## Command architecture and recovery

`ConsoleRepository` remains the UI boundary. Production gains the separate
`ConsoleCommandTransport` capability; read-only injected transports cannot send
commands. Mock transitions stay isolated; mock pumps remain read-only.

`Esp32ConsoleCommands` returns a typed client command ID, then tracks
SENDING → CONFIRMING → CONFIRMED / REJECTED / FAILED / UNKNOWN. IDs are local,
not firmware transaction IDs. HTTP acknowledgement never optimistically changes
equipment state. Matching evidence is evaluated only on a fresh read of that
actuator's status path, not old cached state or a UI update.

Results are per actuator; unresolved UNKNOWN records survive other operations
and a stop replacing a pending dose. Footer prioritizes uncertainty; sheets
show actual reported state and result. Same-actuator pending taps are blocked;
both pumps share a pending gate plus observable mutual exclusion. Stop remains
available during pending motion, but repeated stop taps are blocked. Independent
actuators can be submitted while another is pending.

One serial request queue coordinates commands, targeted status refresh and the
existing approximately two-second non-overlapping polling. Polling continues
between requests; commands/rebuilds create no extra polling loops. Equipment
uses the latest per-path reports instead of overwriting targeted updates with
older cycle data.

The default 12-second confirmation window turns unresolved checking into UNKNOWN.
Later matching LED/UV state or observed feed/dose start followed by idle can
resolve it. If execution cannot be established, UNKNOWN remains visible while
reliable current equipment state recovers. A recovered connection is not proof
of success. A definitely pre-submission connection failure is FAILED; timeout,
interruption after submission, redirect or malformed acknowledgement is UNKNOWN.
Explicit firmware refusal is REJECTED. **No command is retried/replayed automatically.**

Leaving/disposal/host changes invalidate command work, mark pending outcomes
UNKNOWN and suppress obsolete queued submissions/results. Already sent actions
cannot be undone. Timers and transport close independently of subscribers consuming
stream events. Local loss disables new submissions; telemetry keeps its Phase 2A
stale behavior. Reconnection polls actual reports; it never replays a command.
Results are session-local, without a new persistent/cloud audit.

Cloud remains separately Unknown until verified by cloud infrastructure. No
Internet is needed for local polling/control, though firmware NTP requirements
can block chemical doses. Authenticated entry, notification routing suspension,
display restoration and gateway uploads are untouched.

## Transport security

Read `get()` still accepts only six original paths. Separate `sendCommand()`
allows exactly the 13 action paths above: GET, HTTP port 80, no query/fragment,
userinfo or supplied headers; validated private Wi-Fi IPv4 destination or local
hostname resolving to one; pinned DNS, DIRECT routing, no redirects, 3-second
deadline, 64 KiB bounded body. Each request owns a new client and disables
persistent connections (no stale pooled-connection reuse). No Railway/Firebase
credentials attach. Android network-security configuration is unchanged.
The unauthenticated firmware LAN is an existing boundary, not solved here.

## Files and verification

Flutter changes are confined to `mobile_app/lib/features/console/`:

- controllers/console_controller.dart; models/console_command.dart, console_state.dart.
- data/console_repository.dart, console_http_transport.dart, console_http_transport_io.dart,
  esp32_console_parser.dart, esp32_console_repository.dart, mock_console_repository.dart;
  new data/esp32_console_commands.dart.
- screens/console_entry_screen.dart, tank_console_screen.dart.
- widgets/console_command_sheet.dart, console_endpoint_settings.dart,
  console_settings_sheet.dart, console_warning_card.dart; new console_pump_sheet.dart.

Tests: new `mobile_app/test/esp32_console_commands_test.dart` and fixture
`test/fixtures/esp32_248c698/commands.json`; updated console_mode_test.dart,
esp32_console_test.dart, esp32_console_network_test.dart and responses.json.
An earlier synthetic fixture used 10 mL capacity; corrected to source 5 mL,
and remaining volume to 4 mL. Existing coverage is retained, updating obsolete
Phase 2A command-disabled assertions for capable live transports.

Production transport is exercised against real TCP HttpServer sockets using
test-only connectionFactory routing validated private addresses to ephemeral
loopback. Tests cover all 13 operations; UV separation; mismatch/scheduled state;
busy/mutual exclusion; invalid/missing volumes/state; cooldown/persistence/refill
refusal; timeout/outage/recovery without retries; one failing status path; serial
requests/polling; duplicate taps; stop during dosing; uncertain busy skips;
session/config cancellation; rejected paths/redirects; credential absence;
and live sheet presentation. Simulators cannot establish physical output.

Documentation changes: this handoff, ARCHITECTURE.md, DECISIONS.md,
DEVELOPMENT_STATUS.md, INDEX.md, TANK_CONSOLE_FIRMWARE_CONTRACT.md,
TANK_CONSOLE_INTEGRATION_READINESS.md and areas/MOBILE.md.

Final source checks passed: formatting, `git diff --check`, `flutter analyze`
(no issues), 116 focused Console/preview tests and 322 full Flutter tests.
59 new actuator/socket/widget cases supplement the prior 57 focused tests.
Logs live under ignored `mobile_app/build/phase2b-{focused,full,analyze}.log`.
Firmware blob matches the baseline; protected firmware/gateway/backend/web
diffs are empty. Unrelated untracked assets and `.claude/` remain untouched.
Android release build passed (`assembleRelease`, 211.3 s, 61.3 MB). APK:
`mobile_app/build/app/outputs/flutter-apk/app-release.apk`.
SHA-256: `09E5B15345CC49041E958ECC23DCF5E3D55451BE34F8D6DF08D7783736C53064`.
Build log: ignored `mobile_app/build/phase2b-release.log`. Existing Firebase
Kotlin-plugin future-compatibility warnings are non-blocking; dependencies
were not upgraded. There was no physical actuator test in this software phase.

## Physical checklist

**LED and UV may be tested normally. Use a controlled feeder amount/setup.
Initially test syringes empty or with water/test liquid, NOT aquarium chemicals.
Do not bypass firmware safety/cooldowns to make the demo work.**

1. Install the new release APK; sign in normally.
2. Put Android and ESP32 on the same local Wi-Fi; configure the actual IP/host.
3. Test Connection, enter Console, compare telemetry/equipment reports.
4. Toggle LED ON/OFF and compare physical lighting.
5. Toggle UV ON/OFF and compare physical output/schedule interaction.
6. Feed once with controlled contents; observe start/idle and actual food.
7. Safely test a busy feeder: `fed:true` alone proves nothing.
8. Physically check/refill A/B in the test setup and confirm refill explicitly.
   Test fixed dose, stop and carefully supervised full retract.
9. Check mutual-exclusion and two-hour chemical-dose rejection. Water tests still
   use the normal dose path/cooldown. NTP sync may legitimately block dosing.
10. Disconnect Wi-Fi during a command: UNKNOWN/stale/disabled new submissions,
    with no automatic second feed/dose. Reconnect and check reported recovery.
11. Allow a firmware schedule/external gateway command to change equipment;
    Console must follow actual reports. Check gateway uploads continue.
12. Remove Internet while retaining local Wi-Fi; check independent local operation.
13. Receive/tap push while Console is active; it must not eject the mounted UI.
    Check landscape/awake behavior and reliable display restoration on exit.

Still physical-only: motor wiring/stroke/calibration, liquid/food amounts,
UV/LED polarity, actual flashed binary, schedule timing, realistic gateway load,
loss mid-actuation, and mounted Android behavior. Inspect the device before
deliberately submitting again after a non-idempotent UNKNOWN outcome.

# Firmware Area Guide

Status: Current firmware reference for temporary bridge testing
Last reviewed: 2026-09-27

## Current boundary

`esp32-config` is the expanded ESP32/Arduino firmware source for the hardware
integration work; `Aqualogic.ino` remains a smaller starting point. The
collaborator's supplied full firmware copy is synchronized separately so its
dashboard styling is retained. The repository also contains local library
folders for OneWire, DallasTemperature, DIYables LCD I2C, and LiquidCrystal
I2C.

The shared device/software contract is
[`../operations/hardware/HARDWARE_INTEGRATION_CONTRACT.md`](../operations/hardware/HARDWARE_INTEGRATION_CONTRACT.md).
The bridge maps the locally registered UV, normal LED, feeder, and guarded Pump
A/B maintenance-test routes documented there. It also forwards administrator
pump schedules and motor-free refill confirmations. The web maintenance test
uses a water-only firmware route; it does not start the chemical-dose
cooldown. Optional threshold-driven pH auto-dose remains device-local and off
by default. The patch leaves sensor calibration, pins, wiring, feeder, UV, LED,
and syringe motion settings unchanged.

## Router-loss local fallback

The expanded firmware source in `esp32-config` and the supplied full firmware
copy now starts the existing local SoftAP after 12 seconds without STA
connectivity, using `WIFI_AP_STA` so router reconnection continues. After STA
connectivity returns and remains up for 15 seconds, the automatic fallback AP
stops and STA/mDNS operation continues. The manual `/wifi/disconnect` defense
path remains AP-only and suppresses STA retries until `/wifi/reconnect` or its
existing 2-minute safety timeout.

This fallback handles loss of the ESP32-to-router Wi-Fi link. It does not
detect an Internet or Railway outage while the ESP32 remains connected to the
router. Sensor buffering, backlog format, and backlog acknowledgement behavior
remain unchanged. On-device outage/recovery and backlog-sync validation is
still required.

## Schedule clock and syringe safeguards

Daily schedules use router-synchronized NTP wall time configured for
Asia/Manila (`PHT-8`). Schedules and their settings are stored in ESP32 NVS;
schedule execution and chemical dosing pause after a cold boot until the clock
is synchronized. Schedule slots and optional pH auto-dose start disabled. A
slot blocked by pump activity, missing confirmed volume, or the shared
two-hour chemical-dose cooldown is recorded as skipped and is not caught up.

Each syringe is tracked against its 5 mL capacity. At the current 1 mL dose,
five doses consume the estimate. A fresh device requires an operator to check
and confirm the initial fill. Refill confirmation updates the estimate without
moving the motor or changing the shared cooldown; retract is a separate motor
action. Manual chemical doses, both pump schedules, and optional pH auto-dose
share the persisted two-hour minimum. The local dashboard and administrator
controls expose remaining volume, refill requirement, clock state, next
eligibility, and skipped-schedule messages. Hardware validation remains
required for timing, persistence, and physical pump behavior.

## Integration principles

- Keep the firmware focused on sensor reads, actuator control, and small API
  payloads.
- Define and validate a device contract before connecting live hardware to the
  backend.
- Keep Wi-Fi credentials and device secrets out of source control.
- Keep safety limits and manual confirmation in the backend/bridge boundary
  until physical safety behavior is reviewed.
- Keep the ESP32 on the tester's private Wi-Fi. Never create a public tunnel to
  its endpoints.
- Keep firmware credentials and device secrets out of source control and logs.

## Future work

- Agree on sensor calibration and units.
- Replace temporary testing infrastructure only after a reviewed production
  device protocol exists.
- Test failure modes for Wi-Fi loss, stale readings, sensor disconnects, and
  actuator timeout/duplicate delivery.

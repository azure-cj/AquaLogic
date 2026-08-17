# Firmware Area Guide

Status: Current firmware reference for temporary bridge testing
Last reviewed: 2026-08-15

## Current boundary

`Aqualogic.ino` is an ESP32/Arduino starting point. The current calibrated
firmware reference is maintained outside this repository and is read-only for
the v1 bridge task. The repository also contains
local library folders for OneWire, DallasTemperature, DIYables LCD I2C, and
LiquidCrystal I2C. The current web, backend, and Flutter workflows use mock or
demo readings instead of requiring this firmware.

The shared device/software contract is
[`../HARDWARE_INTEGRATION_CONTRACT.md`](../HARDWARE_INTEGRATION_CONTRACT.md).
The temporary bridge maps the locally registered UV, normal LED, feeder, and
guarded Pump A/B manual-test routes documented there. Pump schedules and pH
auto-dose are not connected. Do not change firmware, pins, wiring, or Wi-Fi
configuration as part of this software phase.

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

# Firmware Area Guide

Status: Hardware foundation / future integration
Last reviewed: 2026-07-27

## Current boundary

`Aqualogic.ino` is an ESP32/Arduino starting point. The repository also contains
local library folders for OneWire, DallasTemperature, DIYables LCD I2C, and
LiquidCrystal I2C. The current web, backend, and Flutter workflows use mock or
demo readings instead of requiring this firmware.

The shared device/software contract is
[`../HARDWARE_INTEGRATION_CONTRACT.md`](../HARDWARE_INTEGRATION_CONTRACT.md).
It is draft until both hardware and software owners approve the payload and
failure semantics.

## Integration principles

- Keep the firmware focused on sensor reads, actuator control, and small API
  payloads.
- Define and validate a device contract before connecting live hardware to the
  backend.
- Keep Wi-Fi credentials and device secrets out of source control.
- Add safety limits and manual override behavior before enabling actuators.
- Document offline buffering and retry behavior before deployment.

## Future work

- Agree on sensor calibration and units.
- Define authenticated ingestion and command endpoints.
- Add device identity and health reporting.
- Test failure modes for Wi-Fi loss, stale readings, sensor disconnects, and
  actuator timeout.

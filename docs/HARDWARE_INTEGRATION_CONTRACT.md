# AquaLogic Hardware Integration Contract

Status: Current v1 bridge contract for temporary hardware testing
Last reviewed: 2026-08-17

This document is the shared boundary between the ESP32 firmware and the
software system. The v1 bridge uses the received firmware as a read-only
reference: no firmware, pin, wiring, or Wi-Fi behavior changes are part of this
phase. Physical safety review and production deployment remain future work.

## Current sensor and bridge boundary

The current backend sensor route is:

```text
POST /tanks/{tank_id}/sensors
```

The temporary bridge instead authenticates at:

```text
POST /device-ingestion/readings
```

The bridge device route does not trust a device to choose an arbitrary tank ID.
A registered device identity is mapped to exactly one tank server-side. The
bridge uses the registered device key, never a staff password or browser token.
The browser and backend do not call the local ESP32 directly.

## Reading contract

The software domain uses these canonical fields and units:

| Field | Unit | Required meaning |
| --- | --- | --- |
| `temperature` | °C | Water temperature |
| `ph` | pH scale | Acidity/alkalinity |
| `turbidity` | NTU | Water clarity measurement |
| `dissolved_oxygen` | mg/L | Dissolved oxygen |
| `tds` | ppm | Total dissolved solids |
| `ammonia` | ppm | Ammonia concentration |

The received ESP32 `/data` payload maps `temp_c`, `ph_value`,
`turbidity_ntu`, and `tds_ppm` to the four installed fields. Dissolved oxygen
and ammonia remain nullable/unavailable; they are not submitted as zero.

The backend remains responsible for tank mapping, validation, timestamp
normalization, persistence, threshold evaluation, alert creation, public status
calculation, and freshness. The firmware should not duplicate business rules
that need to remain consistent across web, mobile, and hardware clients.

## Failure behavior

The integration must define and test:

- sensor disconnected or electrically invalid;
- readings outside physically plausible bounds;
- duplicate or retried samples;
- device clock drift and missing timestamps;
- Wi-Fi/API unavailability;
- stale readings and device heartbeat loss;
- partial payloads when one sensor is unavailable;
- actuator timeouts, invalid responses, duplicate delivery, and stale commands.

The software distinguishes a safe reading from a missing or stale reading. The
bridge never fabricates a sensor record. It does not automatically retry an
actuator request after a timeout or ambiguous response because the physical
action may already have happened.

## v1 actuator command contract

The backend creates one command row with:

- server-generated `command_id`;
- registered `device_id` and fixed `tank_id`;
- admin `actor_user_id`;
- one allowlisted actuator/action and validated payload;
- requested, expiry, executing, and execution timestamps;
- `queued`, `executing`, `succeeded`, `failed`, or `expired` status;
- result/error and audit metadata.

The browser command payload is:

```json
{
  "device_id": "esp32-test-01",
  "actuator": "uv",
  "action": "timer",
  "payload": {"duration_ms": 600000}
}
```

Allowed action payloads are:

- UV and normal LED: `on`, `off`, `timer` with 1–86,400,000 ms, and `schedule`
  with `enabled`, `on_time`, and `off_time` in `HH:MM`;
- feeder: `feed_now`, `config` with `open_angle` 0–180 and `duration_ms`
  500–60,000, and `schedule` with exactly three `{enabled,time}` slots.

Pump A/B manual tests add payload-free `dispense`, `stop`, and `retract`.
The firmware's `volume_ml` status value describes the configured dose; the
current dispense routes accept no volume parameter. The bridge waits for that
configured move to report complete and applies a bounded local safety timeout,
with one intentional stop only when completion is not observed. A future
editable dose volume requires a separately reviewed firmware configuration
endpoint and is not implied by this contract.

The device-key bridge contract claims pending commands at
`/device-ingestion/actuators/pending`, marks them executing before a local
request, then reports success/failure and posts refreshed state to
`/device-ingestion/actuator-state`. Claim and final reports are idempotent.
The bridge makes one physical dispense request per command, with status polling
and at most one intentional matching safety stop if the configured move does
not complete. It never retries a request whose execution may already have
happened.

## Firmware actuator boundary used by v1

The current ESP32 reference registers these local routes used by the bridge:

```text
/uv/status /uv/on /uv/off /uv/timer /uv/schedule
/led/status /led/on /led/off /led/timer /led/schedule
/feeder/status /feeder/feed /feeder/config /feeder/schedule
/syringeA/status /syringeA/dispense /syringeA/stop /syringeA/retract
/syringeB/status /syringeB/dispense /syringeB/stop /syringeB/retract
```

The bridge may call only the manual-test pump routes `/syringeA/status`,
`/syringeA/dispense`, `/syringeA/stop`, `/syringeA/retract`, and the matching
`/syringeB/*` routes when the tester-only `pump_manual_test_enabled` flag is
true. It never calls pump schedules, jog/config routes, or pH auto-dose routes,
and never exposes the ESP32 to the internet. Pump tests are restricted to
empty syringes or water; they are not dosing behavior.

No actuator should be enabled in production until timeout, duplicate-command,
manual-override, emergency-stop, and physical fail-safe behavior are reviewed.

## Integration sequence

1. Agree on sensor calibration, units, precision, and error representation.
2. Add a backend simulator using the sensor payload shape.
3. Keep contract tests for valid, invalid, stale, duplicate, and partial
   readings.
4. Keep device registration and authenticated ingestion ahead of live hardware.
5. Connect one test device to one tank and compare device values with manual
   measurements.
6. Test Wi-Fi loss, server restart, sensor disconnects, and stale reports.
7. Validate the temporary v1 actuator bridge on one device and one tank.
8. Review physical safety controls before any production actuator deployment.

Any change to this contract should be reviewed by both hardware and software
owners and recorded in `docs/DECISIONS.md`.

The owner may use one temporary HTTPS tunnel for the dashboard/API during a
test. The ESP32 remains on the tester's private local Wi-Fi; no ESP32 endpoint
is placed behind a tunnel or exposed to the internet. Keep all local bridge
configuration and device keys out of source control.

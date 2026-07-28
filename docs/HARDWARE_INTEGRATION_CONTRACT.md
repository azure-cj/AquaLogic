# AquaLogic Hardware Integration Contract

Status: Draft integration contract
Last reviewed: 2026-07-27

This document is the shared boundary between the ESP32 firmware and the
software system. It is intentionally a draft until the hardware teammate and
software teammate agree on calibration, wiring, device identity, and failure
behavior.

## Current boundary

The current backend sensor route is:

```text
POST /tanks/{tank_id}/sensors
```

It is authenticated for staff/demo use and is not yet a production device
ingestion endpoint. The future device route should not trust a device to choose
an arbitrary tank ID. A device identity should be registered and mapped to a
tank server-side.

## Reading contract

The software domain currently uses these canonical fields and units:

| Field | Unit | Required meaning |
| --- | --- | --- |
| `temperature` | °C | Water temperature |
| `ph` | pH scale | Acidity/alkalinity |
| `turbidity` | NTU | Water clarity measurement |
| `dissolved_oxygen` | mg/L | Dissolved oxygen |
| `tds` | ppm | Total dissolved solids |
| `ammonia` | ppm | Ammonia concentration |

Device payloads should also carry:

- `device_id`: stable server-registered device identity.
- `observed_at`: UTC timestamp from the device or gateway.
- `firmware_version`: useful for diagnosing calibration and protocol changes.
- `reading_id`: optional unique sample ID for retry/idempotency.
- connection or sensor health metadata when a sensor is disconnected or invalid.

Example future payload:

```json
{
  "device_id": "esp32-tank-01",
  "observed_at": "2026-07-27T10:00:00Z",
  "firmware_version": "0.1.0",
  "reading_id": "esp32-tank-01-20260727T100000Z-0001",
  "temperature": 27.4,
  "ph": 7.2,
  "turbidity": 3.1,
  "dissolved_oxygen": 6.4,
  "tds": 220,
  "ammonia": 0.03
}
```

The backend remains responsible for tank mapping, validation, timestamp
normalization, persistence, threshold evaluation, alert creation, and public
status calculation. The firmware should not duplicate business rules that need
to remain consistent across web, mobile, and hardware clients.

## Failure behavior

The integration must define and test:

- sensor disconnected or electrically invalid;
- readings outside physically plausible bounds;
- duplicate or retried samples;
- device clock drift and missing timestamps;
- Wi-Fi/API unavailability;
- stale readings and device heartbeat loss;
- partial payloads when one sensor is unavailable.

The software should distinguish a safe reading from a missing or stale reading.
The firmware should fail safe and avoid activating pumps, dosing, feeders, or
other actuators when command validity or connection state is uncertain.

## Future command contract

Actuator commands should eventually include:

- a server-generated `command_id`;
- registered `device_id` and target actuator;
- command type and bounded parameters;
- creation, expiry, and acknowledgement timestamps;
- device result and failure reason;
- an audit record and manual override path.

No actuator should be enabled in production until timeout, duplicate-command,
manual-override, and emergency-stop behavior are tested.

## Integration sequence

1. Agree on sensor calibration, units, precision, and error representation.
2. Add a backend simulator using this payload shape.
3. Add backend contract tests for valid, invalid, stale, duplicate, and partial
   readings.
4. Add device registration and authenticated ingestion before connecting a real
   ESP32.
5. Connect one test device to one tank and compare device values with manual
   measurements.
6. Test Wi-Fi loss, server restart, sensor disconnect, retries, and stale data.
7. Add actuator commands only after read-only sensor ingestion is reliable.

Any change to this contract should be reviewed by both the hardware and
software owners and recorded in `docs/DECISIONS.md`.

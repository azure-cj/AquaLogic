# Bridge Architecture

## Status

**Implemented Phase 01 bridge hardening** — reviewed 2026-08-21.

## 1. Purpose
Define the bridge that currently allows the remotely located hardware team and software team to integrate and test AquaLogic.

## 2. Related Requirements
- FR-05 Sensor Data Transmission
- NFR-03 Device Security
- NFR-04 Data Protection
- NFR-07 Reliability

## 3. Current Context
**Implemented local testing architecture**

Because the hardware and software developers are working from separate locations, AquaLogic uses a bridge so ESP32 sensor data and equipment communication can be tested remotely against the AquaLogic backend.

The current bridge is the owner-operated Python process at
`bridge/esp32_bridge.py`. It polls the ESP32 `/data` endpoint, validates and
translates the four installed sensor fields, then posts them to the backend
with `X-Device-Key`. The backend supplies the fixed tank mapping and remains
responsible for persistence, freshness, thresholds, alerts, and public status.

## 4. Bridge Responsibilities
The bridge should be responsible for:

- authenticating as a registered device-side component
- forwarding supported sensor readings
- carrying equipment communication between backend and hardware
- preserving device/tank identity
- reporting connectivity/freshness information
- handling temporary network interruption safely

The bridge may also carry the separately documented actuator command flow. That
equipment behavior belongs to Phase 05; Phase 01 owns the sensor-ingestion
trust boundary and reading contract.

## 5. Bridge Non-Responsibilities
The bridge should not:

- determine whether water quality is Normal, Warning, or Critical
- generate business-level alerts on its own
- use staff login credentials
- bypass backend authorization
- directly mutate unrelated application data

## 6. Security
- Device-side authentication uses its own credential/device key.
- Sensitive keys must not be exposed in browser UI, screenshots, logs, or repository files.
- Backend authorization remains authoritative.
- Network or payload failures must not fabricate a reading or select a different
  tank.

## 7. Implemented Phase 01 Hardening

- Keep the current HTTP/JSON bridge transport and device-key header for the
  local release.
- Add contract coverage for valid payloads, missing/extra fields, non-finite or
  out-of-range values, invalid device keys, fixed tank mapping, and optional
  observation timestamps. The bridge translator ignores unrelated firmware
  status fields, while the backend reading schema rejects extra request fields.
- Preserve the current no-automatic-deduplication behavior because the hardware
  payload has no stable sample identifier. A future sample ID can be added when
  the device contract provides one.
- Keep production bridge deployment and high-availability reconnect policy
  deferred until the hardware deployment target is selected.

## 8. Deferred Scope

- Direct ESP32-to-backend communication.
- Public exposure of the ESP32 or its local endpoints.
- Production bridge hosting, failover, and fleet orchestration.
- Stable sample IDs and duplicate-reading suppression.

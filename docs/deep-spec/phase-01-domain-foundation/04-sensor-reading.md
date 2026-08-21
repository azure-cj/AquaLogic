# Sensor Reading Model

## Status

**Implemented Phase 01 reading hardening** — reviewed 2026-08-21.

## 1. Purpose
Define what counts as a valid sensor reading in AquaLogic.

## 2. Related Requirements
- FR-04 Water Quality Monitoring
- FR-05 Sensor Data Transmission
- FR-06 Water Quality Status Evaluation
- NFR-08 Accuracy
- NFR-18 Data Integrity

## 3. Current Reading Contract

The current wide reading model stores one timestamped payload per tank with:

- Temperature
- pH
- Turbidity
- TDS
- dissolved oxygen, nullable compatibility field
- ammonia, nullable compatibility field
- `is_mock` source marker

The current bridge contract sends only temperature, pH, turbidity, and TDS. The
deferred dissolved-oxygen and ammonia fields remain in persistence and response
models for compatibility, but stay hidden from current user-facing sensor and
threshold workflows and are not sent by the bridge.

## 4. Approved Reading Provenance

Phase 01 now provides:

- nullable `device_id`, linked to the registered source device for bridge
  readings and left null for manual readings;
- server-side `received_at`, recorded in UTC when the backend accepts the
  reading;
- the existing timestamp field retained as the observation timestamp for API
  compatibility and hardware clock analysis.

No separate per-parameter rows or validation-status workflow was added.
The current wide payload remains the domain shape used by thresholds, alerts,
analytics, and public serialization.

## 5. Business Rules
- BR-001: Unsupported parameters must not silently enter normal monitoring flows.
- BR-002: Invalid or malformed values must be rejected or explicitly marked invalid.
- BR-003: Old readings may remain visible historically but must not be treated as fresh.
- BR-004: Missing one parameter must not invalidate all other valid parameters.
- BR-005: Device readings use the fixed server-side device/tank mapping and retain
  their source device when accepted.
- BR-006: Manual readings have a null source device and a server-generated
  receipt timestamp.
- BR-007: Freshness decisions use the server receipt boundary introduced by this
  hardening pass, while observation time remains available for history and clock
  drift diagnostics.
- BR-008: Duplicate samples are not suppressed until the hardware contract
  provides a stable sample identifier.

## 6. Validation Rules

The installed bridge fields use these current bounds:

| Field | Unit | Accepted range |
|---|---|---:|
| temperature | °C | -10 to 60 |
| pH | pH scale | 0 to 14 |
| turbidity | NTU | 0 to 3000 |
| TDS | ppm | 0 to 5000 |

Manual and device-created readings use the same validation policy. Missing
deferred parameters remain unavailable rather than being represented as zero.

## 7. Deferred Scope

- Dissolved-oxygen and ammonia hardware integration and user-facing controls.
- Stable hardware sample IDs and duplicate suppression.
- Per-parameter reading tables or a persisted validation-status lifecycle.
- Automatic correction of device clock drift.

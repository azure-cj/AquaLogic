# Monitoring Device

## Status

**Implemented Phase 01 device lifecycle** — reviewed 2026-08-21.

## 1. Purpose
Define the ESP32-based monitoring hardware as a registered AquaLogic device.

## 2. Related Requirements
- FR-05 Sensor Data Transmission
- NFR-03 Device Security
- NFR-07 Reliability
- NFR-18 Data Integrity

## 3. Current Implementation
**Implemented**

The current architecture uses a local Python bridge and ESP32-based monitoring
hardware that communicates with the backend through a registered device key.
`RegisteredDevice` currently stores:

- device identifier
- fixed tank ID
- hashed device key
- active/inactive state
- creation timestamp
- last-seen timestamp

Provisioning is administrator-only, returns the raw key once, and never returns
the key from later responses. A device is permanently mapped to one tank in the
current model. Multiple active devices may be mapped to the same tank.

## 4. Derived Connection State

Connection status is derived and is not stored as a separate status column:

- **Online:** active device seen within the 90-second bridge freshness window.
- **Offline:** active device has never been seen or is outside that window.
- **Disabled:** device is inactive, regardless of its last-seen timestamp.

This status describes the device connection, not the tank's water-quality
status.

## 5. States
Current derived state model:

```text
Registered → Online
     │          │
     │          └── freshness window passes → Offline
     └──────────────→ Disabled
```

## 6. Business Rules
- BR-001: Device authentication must not use staff passwords or staff sessions.
- BR-002: Unknown or invalid device credentials must not be accepted.
- BR-003: A reading must be associated with an authorized device/tank mapping.
- BR-004: A stale or offline device must not appear healthy merely because old readings exist.
- BR-005: Deactivating a device immediately rejects bridge ingestion and device
  actuator operations while preserving its historical records.
- BR-006: Rotating a device key invalidates the previous key and reveals the new
  key only in the rotation response.
- BR-007: Device list/detail responses never expose raw keys, key hashes, or
  other bridge secrets.

## 7. Implemented Phase 01 Hardening

Add an administrator-only device management surface in both backend and web:

- list and inspect registered devices
- show tank mapping, derived connection state, created time, and last seen time
- activate or deactivate a device
- rotate a device key and display the replacement once

Device deletion is not part of the first lifecycle pass. Deactivation or key
rotation is the recoverable replacement mechanism. Historical readings will
retain their nullable source-device reference if a device is later retired.

The web surface is an administrator-only `/admin/devices` workspace under
Configure. It supports status filtering, activation changes, and confirmation-
gated one-time key rotation without persisting device keys in browser storage.

## 8. Deferred Scope

- One-device-per-tank enforcement or a primary-device designation.
- Device reassignment workflows.
- Firmware/version inventory until the bridge supplies an authoritative value.

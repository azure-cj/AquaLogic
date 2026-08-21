# AquaLogic System Map

## Core System View

AquaLogic is organized around the **tank** as the central operational object.

```text
                     ┌── Fish Species
                     │
                     ├── Species Care
                     │
Monitoring Device ─ Tank ─ Alerts
        │            │
     Readings        ├── Analytics
        │            │
   Thresholds        ├── Public Page
                     │
                     └── Equipment
```

## Monitoring Flow

```text
Sensors
  ↓
ESP32 / Monitoring Device
  ↓
Bridge
  ↓
AquaLogic Backend
  ↓
Reading Validation
  ↓
Threshold Evaluation
  ↓
Tank Status
  ↓
Alert
  ↓
Notification
```

## Equipment Flow

```text
Authorized Admin
  ↓
AquaLogic UI
  ↓
Backend Validation
  ↓
Command Queue / Lifecycle
  ↓
Bridge / Equipment Connection
  ↓
Actuator
  ↓
Execution Result
  ↓
Command History / Audit
```

## Current Important Boundaries

- The bridge transports authenticated hardware data/commands.
- The backend owns business rules.
- The bridge should not decide whether water is safe.
- Staff authentication and device authentication are separate concerns.
- Stale or missing readings must not be treated as normal readings.
- Breeding-specific management is deferred.

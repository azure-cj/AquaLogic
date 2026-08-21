# Deep-Spec Workflow

Use this order when hardening AquaLogic.

## Phase 1 — Domain Foundation
Lock down:
- Tank
- Monitoring Device
- Bridge
- Sensor Reading
- Fish Species

## Phase 2 — Monitoring Engine
Lock down:
- Global Thresholds
- Reading Validation
- Water Status
- Freshness
- Alert Lifecycle
- Notifications

## Phase 3 — Species Care
Lock down:
- Species Profiles
- Water Suitability
- Fish-to-Fish Compatibility
- Tank Assignment

Breeding remains deferred.

## Phase 4 — Operations
Lock down:
- Fleet Overview
- Tank Workspace
- Alert History
- Analytics
- Public Pages

## Phase 5 — Equipment Control
Lock down:
- Equipment Connection
- UV / Lighting
- Feeder
- Feeding Schedules
- Pump Maintenance
- Command Lifecycle
- Command History / Audit

## Phase 6 — Access and Platform
Lock down:
- Authentication
- Account Security
- Staff / Roles
- Permission Matrix
- Data Integrity
- Backup / Recovery

## Rule Before Coding
For each file:

1. Confirm what the current backend actually does.
2. Replace assumptions with confirmed behavior.
3. Mark inconsistencies.
4. Decide only what is necessary.
5. Implement the approved gap.
6. Update the spec to match.

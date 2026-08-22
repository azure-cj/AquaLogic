# Deep-Spec Workflow

Status: Current specification workflow
Last reviewed: 2026-08-22

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
- Notifications (current surface: in-app only; external delivery deferred)

## Phase 3 — Species Care
Lock down:
- Species Profiles
- Water Suitability
- Fish-to-Fish Compatibility (notes-only; structured compatibility deferred)
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

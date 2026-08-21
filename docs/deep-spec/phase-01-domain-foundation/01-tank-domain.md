# Tank Domain

## Status

**Implemented Phase 01 foundation hardening** — reviewed 2026-08-21.

The tank entity and its Phase 01 device-boundary rules are implemented without
expanding tank operations, alerts, species suitability, or actuator behavior
owned by later phases.

## 1. Purpose
Define what a tank means inside AquaLogic and what information and relationships belong to it.

## 2. Related Requirements
- FR-03 Tank Management
- FR-04 Water Quality Monitoring
- FR-08 Operations Dashboard
- FR-13 Species Suitability Guidance
- FR-15 Public Tank Pages
- FR-16 Actuator Status and Control

## 3. Current Implementation
**Implemented**

Current tank workspace behavior visible in the system includes:

- tank name
- tank code
- description
- location
- water type
- volume
- habitat label
- established date
- customer assignment
- assigned fish species
- operational water status
- latest reading time
- current readings
- operational alerts
- species-care status
- public-page status
- public care notes
- QR / public link actions
- actuator snapshot and access to full controls

## 4. Actors
- Administrator
- Staff
- Monitoring Device
- AquaLogic Backend
- Public Viewer, where public pages are enabled

## 5. Core Relationships
A tank may relate to:

- zero or more assigned fish species
- one or more registered monitoring devices; multiple active devices remain
  supported for the current release
- sensor readings
- alerts
- actuator commands
- public-page configuration

## 6. States
Current visible states include:

- Normal
- Warning
- Critical
- Offline

Tank operational status is derived from the latest reading and its freshness.
It is separate from the registered-device connection status, which is derived
from device activity and activation state.

A separate Species Care state may include:

- Suitable
- Attention
- Insufficient Data / Unavailable

## 7. Business Rules
- BR-001: A tank may exist even when no recent device reading is available.
- BR-002: Offline or stale monitoring must not be displayed as Normal.
- BR-003: Historical records must remain associated with the correct tank.
- BR-004: Public information must remain separate from internal operational data.
- BR-005: Tank names and non-null tank codes are unique; tank codes remain
  editable.
- BR-006: Deleting a customer preserves its tanks and sets their customer
  reference to null.
- BR-007: Deleting a tank cascades its dependent readings, alerts, assignments,
  registered devices, and actuator records according to the current migration
  contract.
- BR-008: A tank may have multiple active devices for now. Any operation that
  needs a device must use an explicit mapping when more than one active device
  is available.

## 8. Implemented Phase 01 Hardening

- Keep the current tank schema and deletion behavior.
- Record the originating device and server receipt time on new sensor readings;
  manual readings will have no device reference.
- Keep device connection status derived rather than adding a persisted tank or
  device status field.
- Treat a future primary-device or device-assignment policy as a follow-up,
  because the current multi-device capability may change later.

## 9. Deferred Scope
- Breeding-record management is not part of the current tank domain.
- A primary-device designation or one-device-per-tank constraint.

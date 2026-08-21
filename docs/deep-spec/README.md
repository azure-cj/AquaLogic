# AquaLogic Deep Feature Specification

This folder is the specification layer beneath the AquaLogic SRS.

The SRS states **what the system provides**. These deep-spec documents define **how the implemented features actually behave**, including rules, states, edge cases, permissions, history, and acceptance criteria.

## Working Principle

Use two passes for every feature:

1. **Reverse-specification** — document what AquaLogic already does today.
2. **Hardening** — identify ambiguous behavior, edge cases, and decisions that must be locked down.

Do not use these files as an excuse to add more modules. The goal is **depth, consistency, and defensibility**, not feature count.

## Status Labels

Use these labels when documenting behavior:

- **Implemented** — confirmed in the current system.
- **Partially implemented** — exists but behavior is incomplete or inconsistent.
- **Decision required** — behavior is unclear and must be decided.
- **Deferred** — intentionally outside the current scope.

## Current Development Context

The software and hardware developers are working remotely from separate locations. AquaLogic currently uses a bridge between the ESP32/hardware side and the backend so integration and testing can continue remotely.

The bridge is therefore part of the current architecture and should be documented clearly rather than removed as an undefined term.

## Current Deep-Spec Phases

1. Domain foundation
2. Monitoring engine
3. Species care
4. Operations
5. Equipment control
6. Access and platform

Breeding-specific management is deferred for now.

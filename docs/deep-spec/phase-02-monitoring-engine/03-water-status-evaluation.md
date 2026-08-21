# Water Status Evaluation

**Current implementation and Phase 02 hardening record — reviewed 2026-08-21.**

## 1. Purpose

Define how accepted readings become Normal, Warning, Critical, or Offline
operational states.

## 2. Current states

- Normal
- Warning
- Critical
- Offline

Offline is the single user-facing state for a missing or stale operational
reading. Parameter-level responses may additionally use Unavailable when a
value is missing or its threshold is disabled.

## 3. Evaluation rules

- No reading is Offline.
- A reading older than 90 seconds by server `received_at` is Offline.
- For a fresh reading, each present and enabled parameter is evaluated against
  its threshold.
- Missing parameters are Unavailable and do not become Normal by default.
- The overall tank status is the worst severity among present, fresh, enabled
  values: Critical dominates Warning, which dominates Normal.
- If no usable fresh value exists, the overall tank status is Offline.
- Exact warning and critical boundary values remain Normal; only strict
  out-of-range values receive Warning or Critical.

Observation timestamps remain available for historical context, but receipt
timestamps drive freshness and operational latest-reading selection.

## 4. Deferred behavior

There is no separate Stale state, per-device status aggregation in this engine,
or external notification behavior. Per-tank threshold overrides remain deferred.


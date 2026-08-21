# Data Freshness

**Current implementation and Phase 02 hardening record — reviewed 2026-08-21.**

## 1. Purpose

Define how AquaLogic determines whether sensor data is current enough to trust
operationally.

## 2. Current rule

The freshness window is 90 seconds. Freshness is calculated from the server
generated `received_at` timestamp. The observation timestamp may be older or
incorrect because it represents the hardware clock and is retained only for
diagnostics and historical display.

```text
now - received_at <= 90 seconds  → current
now - received_at >  90 seconds  → offline
```

Missing readings and stale readings share the same user-facing Offline state.
The API and UI may still show the latest observation time and reporting age so
staff can understand what happened.

## 3. Recovery behavior

A new accepted reading immediately becomes the current operational reading and
can return a tank to Normal, Warning, or Critical according to its values.
Historical stale readings remain available for context and analytics.

Species Care and other derived workflows must not treat a stale reading as a
fresh confident result.

## 4. Deferred behavior

Separate Stale and Offline labels, parameter-specific freshness windows, and
external freshness notifications are deferred.


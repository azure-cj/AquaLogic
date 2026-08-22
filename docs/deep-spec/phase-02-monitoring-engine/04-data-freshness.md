# Data Freshness

**Current implementation and Phase 02 hardening record — reviewed 2026-08-22.**

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

The persistent monitoring-outage incident is a separate, tank-level operational
record. Its configurable grace period defaults to 900 seconds and does not
change the 90-second request-time Offline state. It opens only for an eligible
active tank expected to report and recovers on a fresh accepted reading; it does
not turn a stale value into a current value.

Authenticated fleet responses expose `reporting_age_seconds`, and authenticated
tank operations readings expose server `received_at`; the web uses those receipt
times for reporting-age copy. Offline values remain visible as last-known
context. Observation `timestamp` is labeled separately as observed time and is
not used to explain freshness.

## 3. Recovery behavior

A new accepted reading immediately becomes the current operational reading and
can return a tank to Normal, Warning, or Critical according to its values.
Historical stale readings remain available for context and analytics.

Species Care and other derived workflows must not treat a stale reading as a
fresh confident result.

## 4. Deferred behavior

Separate Stale and Offline labels, parameter-specific freshness windows, and
external freshness notifications are deferred. The in-app monitoring-incident
history is implemented without adding external delivery.

# Notification Behavior

**Current implementation boundary — reviewed 2026-08-21.**

## 1. Purpose

Separate the persistent operational alert from the mechanism used to surface it
to users.

## 2. Current release behavior

An Alert is a persistent system record representing an abnormal water-quality
condition. The current notification surface is in-app only:

- dashboard warning and critical counts;
- the alert badge and alert feed;
- tank and fleet operational alert panels;
- filtered alert history for investigation and resolution.

```text
Abnormal condition
  ↓
Alert created or updated
  ↓
In-app alert surfaces
```

Automatic resolutions remain visible in alert history and are recorded in the
administrator-only audit stream.

The in-app Alerts area also exposes a distinct Monitoring outages history backed
by persistent tank-level monitoring incidents. It is not an alert severity,
does not claim water-quality recovery, and has no manual-resolve action. An
accepted reading resolves the outage incident automatically; external delivery
remains outside this phase.

## 3. Deferred behavior

Email, push, SMS, notification preferences, delivery workers, provider
configuration, retry policy, and separate notification history are not part of
Phase 02. They require a separate notification design and operational boundary.

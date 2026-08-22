# Alert Lifecycle

**Current implementation and Phase 02 hardening record — reviewed 2026-08-22.**

## 1. Purpose

Define how threshold events become alerts and how those alerts are handled over
time.

## 2. Alert identity and transitions

There is at most one active alert for a tank and parameter.

```text
No active alert
  ├─ abnormal reading ──> Active Warning/Critical
  └─ normal reading ────> no alert

Active Warning  ──critical reading──> Active Critical
Active Critical ──warning reading───> Active Warning
Active alert    ──normal reading────> System-resolved
Active alert    ──operator action───> Operator-resolved
Resolved alert  ──later abnormal────> New alert incident
```

Warning and Critical reflect the latest abnormal reading. A normal reading
resolves only the alert for the same parameter. A missing value does not resolve
an alert.

Persistent monitoring-outage incidents are not water-quality alerts. They have
their own tank-level history and lifecycle: the background detector opens one
after the outage grace period, and the same accepted reading may both recover
the monitoring incident and create or update a water-quality alert according to
its values. Invalid, heartbeat, and no-reading events do not recover it.

Threshold changes are prospective. Disabling a threshold does not alter an
active alert at save time; the next usable reading resolves it with the system
reason `threshold_disabled`.

## 3. Resolution history

Alerts preserve their creation and resolution timestamps, original reading
reference, and final severity. The additive `resolution_source` field is:

- `operator` for a manual Mark handled action (the backend route remains
  `/alerts/{alert_id}/resolve` for compatibility);
- `system` for a normal-reading or disabled-threshold resolution;
- `null` for unresolved alerts and legacy resolved records whose source is
  unknown.

Automatic resolutions create an administrator-visible `alert.auto_resolve`
security audit event containing the alert, parameter, triggering reading, and
reason. They do not identify a human actor.

## 4. Current UI behavior

Staff can filter alert history by tank, severity, parameter, state, and date.
Staff may mark alerts handled. This closes the persistent record and removes it
from the active queue, but does not require or imply a fresh Normal reading; a
later abnormal reading may create a new incident. The in-app alert feed,
dashboard counts, and alert badge are the current notification surface.

Acknowledged, reopened, recurring-alert aggregation, and external notification
delivery states are not introduced in this phase.

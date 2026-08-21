# Alert History

Last reviewed: 2026-08-21
Status: Implemented Phase 02 alert lifecycle and current operations history view

## 1. Purpose

Provide an explainable, filterable record of abnormal water-quality conditions
and their operator or system resolution.

## 2. Related Requirements

- FR-07 Alert Management
- FR-08 Operations Dashboard
- FR-10 Analytics and Trends
- NFR-04 Role-Based Access Control

## 3. Current Interfaces

The authenticated alert routes are:

| Method | Route | Purpose |
| --- | --- | --- |
| GET | `/alerts` | List active alerts by default, or all alerts when requested |
| GET | `/tanks/{tank_id}/alerts` | List alerts for one tank |
| GET | `/alerts/history` | Filter alert history |
| PUT | `/alerts/{alert_id}/resolve` | Resolve one alert as an operator |

The web route is `/admin/alerts`. Staff and administrators can read and resolve
alerts. Public viewers cannot access alert history.

## 4. Alert Identity and Lifecycle

There is at most one active alert for a tank and parameter:

```text
abnormal reading -> active Warning/Critical alert
Warning -> Critical when severity escalates
Critical -> Warning when a later reading improves but remains abnormal
normal same-parameter reading -> system resolution
operator action -> operator resolution
later abnormal period -> new incident after resolution
```

Missing values do not resolve an active alert. Threshold changes are
prospective. Disabling a threshold resolves an active matching alert only when
the next usable reading is processed, with the system reason
`threshold_disabled`.

## 5. Filtering and Response Behavior

`GET /alerts/history` supports:

- `tank_id`
- `severity`
- `parameter`
- `resolved`
- `created_after`
- `created_before`

Results are returned newest first. Alert responses include tank and reading
references, parameter, severity, message, created time, resolution state,
resolution time, resolver ID when applicable, and nullable `resolution_source`.

`resolution_source` is:

- `operator` for a staff or administrator Resolve action;
- `system` for automatic normal-reading or threshold-disabled resolution;
- `null` for unresolved alerts and legacy resolved rows with unknown origin.

## 6. Current UI Behavior

The alert page provides tank, severity, parameter, state, and date filters. Each
row shows the condition, tank, severity, creation time, and current state. An
unresolved alert has a Resolve action. A resolved alert identifies whether it
was operator-resolved, automatically resolved, or has an unknown legacy source.

Fleet Overview shows a bounded recent unresolved-alert feed and links to the
full history view. Analytics can display alert markers and events in the
selected reporting window.

Loading, error, no-results, and all-clear states are explicit. The browser does
not expose raw audit request data, credentials, token material, or device data.

## 7. Audit Behavior

Operator resolution creates an `alert.resolve` audit event. Automatic resolution
creates an administrator-visible `alert.auto_resolve` event containing the alert
ID, parameter, triggering reading ID, and resolution reason. Audit events do not
store secrets or unnecessary request payloads.

## 8. Notification Surface

The current notification surface is in-app only:

- alert badge;
- dashboard warning and critical counts;
- Fleet Overview recent-alert feed;
- tank operations alert panel;
- filtered Alert History.

Email, push, SMS, delivery workers, notification preferences, retries, and
separate notification history are not implemented.

## 9. Edge Cases and Permissions

- Staff and administrators can resolve alerts; unauthenticated and public users
  are rejected.
- Resolving an already resolved alert is idempotent and does not create a second
  resolution.
- A missing alert returns not found.
- A missing or stale reading may leave an alert active; lack of data is not
  treated as a normal reading.
- Alert history remains available after resolution for investigation.

## 10. Approved Hardening

- Preserve the Phase 02 resolution-source and automatic-resolution audit
  contract.
- Keep alert history terminology consistent across Fleet Overview, Analytics,
  Tank Workspace, and the dedicated alert page.

## 11. Deferred Scope

- Server-side pagination or cursor navigation for large alert histories.
- Acknowledged, snoozed, reopened, or recurring-alert aggregation states.
- External notification delivery and notification history.
- Predictive alerting and business-intelligence reporting.

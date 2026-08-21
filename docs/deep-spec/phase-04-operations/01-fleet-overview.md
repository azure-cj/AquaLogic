# Fleet Overview

Last reviewed: 2026-08-21
Status: Implemented current operations view; scale hardening deferred

## 1. Purpose

Provide the staff command center for answering whether the managed fleet is
healthy, which tank needs attention, what is wrong, and how recent the data is.

## 2. Related Requirements

- FR-08 Operations Dashboard
- FR-10 Analytics and Trends
- NFR-07 Reliability

## 3. Current Implementation

The authenticated `GET /fleet` route is available to staff and administrators.
The web route is `/admin/fleet`. It currently combines:

- total tank count and Normal, Warning, Critical, and Offline counts;
- a tank-health table with location, current temperature, pH, reporting age,
  assigned-species count, and Species Care status;
- active warning and critical alert counts per tank;
- a recent unresolved-alert feed with links to Alert History;
- selectable 24-hour, 7-day, and 30-day reporting-uptime summaries;
- status filters for all tanks and tanks needing action.

The fleet page refreshes fleet, unresolved-alert, and uptime data every 30
seconds. Loading, error, and empty-alert states are visible in the page rather
than being represented as healthy fleet data.

## 4. Actors and Permissions

- Staff may read fleet status and navigate to the staff workspaces.
- Administrators have the same read access plus the administrator mutations
  documented by the relevant tank, threshold, device, and actuator specs.
- Public viewers use the separate public tank route and never receive the
  authenticated fleet response.

Backend authorization remains authoritative even when a navigation item or
action is hidden in the web client.

## 5. Status and Freshness Rules

Fleet tank status uses the Phase 02 operational states:

- **Normal:** all present, fresh, enabled values are within their configured
  ranges.
- **Warning:** at least one present, fresh, enabled value is Warning and none
  is Critical.
- **Critical:** at least one present, fresh, enabled value is Critical.
- **Offline:** no reading exists or no usable fresh value exists.

The latest reading is selected by server `received_at`. `reporting_age_seconds`
is derived from that receipt time. The API's `last_reading_at` retains the
reading's observation timestamp for historical and hardware-clock context.
Missing parameters are unavailable and do not become Normal by default.

Species Care is advisory context only. Its `suitable`, `attention`, and
`unavailable` states do not change operational tank status or alert counts.

## 6. Main Workflow

1. Staff opens Fleet Overview.
2. The page loads tank status, unresolved alerts, and reporting uptime.
3. The operator filters to Warning, Critical, Offline, or Needs action.
4. The operator opens a tank workspace or Alert History for investigation.
5. The operator uses the tank or alert workspace for the authorized follow-up
   action.

## 7. Backend and API Behavior

`GET /fleet` returns one summary per tank, ordered by tank name. The response
includes tank identity, public identifier, internal location, optional customer
summary, latest reading, operational status, observation-time display value,
receipt-based reporting age, alert counts, Species Care summary, and assigned
species count.

The endpoint does not paginate the fleet and does not expose device keys,
threshold internals, raw security events, or public-only response data.

## 8. UI States and Edge Cases

- An empty fleet displays an empty state rather than a false all-clear result.
- A tank without a reading is Offline and has no reporting age.
- A stale tank remains visible so staff can investigate the missing report.
- A failed fleet, alert, or uptime request displays an independent error state
  with retry behavior.
- An empty unresolved-alert feed displays an all-clear message.
- Fleet counts and filters use the same status values shown in the tank rows.

## 9. Approved Hardening

- Keep receipt-time freshness and latest-reading semantics aligned with Phase
  02 throughout the fleet response and any future server-side aggregation.
- Preserve explicit distinctions between observation time and receipt time in
  labels and operational explanations.

## 10. History and Audit

Fleet Overview is a read-only derived view. It does not create history or audit
events. Follow-up actions are audited by the owning tank, alert, threshold,
device, species, or actuator workflow.

## 11. Deferred Scope

- Fleet and alert pagination for larger datasets.
- WebSocket or push-based fleet updates.
- Predictive maintenance, forecasting, and business-intelligence reporting.
- Customer-facing fleet access or customer tank ownership workflows.

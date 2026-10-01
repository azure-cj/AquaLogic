# Analytics

Last reviewed: 2026-10-01
Status: Implemented split observation-time and receipt-time analytics

## 1. Purpose

Provide operational trend analysis for water quality, alert activity, and
reporting health without becoming a general business-intelligence platform.

## 2. Related Requirements

- FR-10 Analytics and Trends
- FR-04 Water Quality Monitoring
- NFR-07 Reliability

## 3. Current Implementation

The authenticated route is `GET /analytics/fleet`. The web route is
`/admin/analytics`, available to staff and administrators.

The current user-facing analytics set supports:

- Temperature
- pH
- Turbidity
- TDS

Dissolved oxygen and ammonia remain nullable compatibility fields in internal
reading/API structures, but they are not exposed as current web metric options,
threshold workflows, or active analytics features.

The response provides:

- complete nullable fleet timelines;
- selected tank overlays for up to three tanks;
- current and previous-period metric statistics;
- fleet averages, minimums, and maximums;
- alert counts, bucketed alert series, and exact alert events;
- historical threshold segments from effective threshold revisions;
- per-tank reporting uptime and classified uptime state;
- current versus previous uptime comparison;
- reporting-gap count and operational insight fields.

The web client persists range, resolution, tank, and metric selections in the
URL and exports the visible analytics dataset as CSV.

## 4. Query Contract

Supported ranges are `24h`, `7d`, `30d`, and `custom`. Custom requests require
ISO `start` and `end` values and may not exceed 30 days.

Supported resolutions are:

- `auto`
- `15m`
- `1h`
- `6h`
- `1d`

Responses are capped at 1,000 buckets. Up to three unique `tank_id` values may
be selected for comparison. The response identifies the selected window,
bucket size, and `Asia/Manila` display timezone.

## 5. Current Calculation Rules

- Water-quality readings are filtered and bucketed by observation time. Each
  metric is averaged within those buckets; missing metric values do not
  contribute to that metric's average.
- Empty buckets remain in the timeline with null metric values and zero sample
  count. Reporting-gap diagnostics are calculated independently from receipt
  time.
- Alert events are placed by alert creation time and retain the linked reading
  value when available.
- Threshold overlays use the effective historical threshold revisions rather
  than applying today's thresholds retroactively.
- Reporting uptime counts unique 30-second reporting intervals against the
  expected interval count for each tank.
- Uptime is classified as healthy at or above the configured warning threshold,
  degraded at or above the configured critical threshold, critical below that,
  and no-data when no interval was reported.
- Reporting gaps count contiguous missing bucket runs per tank.
- Water-quality previous-period comparisons use the equivalent preceding
  observation-time window.
- Reporting uptime and reporting-gap calculations use server receipt time.
- Percentage change is unavailable when the previous average is missing or zero.

## 6. Timestamp Boundary

Analytics keeps observation and receipt time as separate calculation inputs:

- `SensorReading.timestamp` is the observation time used to filter, order, and
  bucket temperature, pH, turbidity, and TDS history. Metric sample counts,
  contributor counts, fleet and selected-tank averages, minimums, maximums,
  current/previous comparisons, and primary-driver comparisons follow this
  observation-time selection.
- `SensorReading.received_at` is the server receipt time used for accepted
  report intervals, uptime, and reporting-gap diagnostics. Tank freshness,
  Offline status, monitoring incidents and recovery, latest accepted report
  selection, and `RegisteredDevice.last_seen_at` continue to use receipt time.
- `Alert.created_at` continues to place alert events and alert buckets.

Rows may be selected for the calculation pass when either timestamp falls in
the requested current/previous windows. Each calculation then applies its own
timestamp window, so an old observation replayed now affects reporting health
at receipt time while its water-quality value stays in its observation period.

ESP32 backlog observations are still approximate: the current firmware backlog
record contains sequence and sensor values but no capture timestamp, so the
bridge estimates `observed_at` from sequence and outage timing.

## 7. UI Behavior

Analytics provides loading, error, invalid-range, empty-data, and responsive
states. Charts show fleet context, selected tank overlays, threshold context,
alert markers, reporting gaps, and comparison information. Alert markers can
open the relevant alert context.

Analytics is diagnostic and read-only. It does not edit thresholds, resolve
alerts, create suitability results, or send notifications. Persistent
monitoring-outage incidents do not replace reporting-gap reconstruction: gap
diagnostics remain derived from receipt-time buckets, while incident history is
an authenticated operational record available in the monitoring-outage view.

## 8. Security and Data Boundaries

- Analytics requires an authenticated staff or administrator session.
- Public viewers use the separate public tank route.
- Device-key bridge credentials cannot access analytics.
- The response does not expose refresh tokens, device keys, security audit
  payloads, or other authentication secrets.

## 9. Implemented Hardening

- Analytics water-quality filtering, ordering, bucket placement, statistics,
  and comparisons use `SensorReading.timestamp`; reporting intervals, uptime,
  and reporting-gap detection use `received_at`.
- Regression coverage verifies recovered observation-time buckets and counts,
  observation-time current/previous statistics and primary-driver comparisons,
  receipt-time uptime and gaps, freshness, and alert creation-time placement.
- Nullable timelines, historical threshold segments, previous-period
  comparisons, alert timing, and deferred metric compatibility are preserved.

## 10. Deferred Scope

- Database-level aggregation, rollups, and large-fleet optimization.
- Windows longer than 30 days or more than 1,000 buckets.
- Server-side scheduled reports and report subscriptions.
- Predictive analytics, forecasting, and business-intelligence modules.
- WebSocket or push-based live analytics updates.
- Analytics controls for dissolved oxygen or ammonia.

# Water Suitability

Last reviewed: 2026-08-21
Status: Implemented advisory evaluation with deferred metrics excluded

## 1. Purpose

Compare assigned species preferences with the tank's latest supported reading
and explain whether the current water is suitable for the assigned species. The
result is advisory guidance and is separate from operational threshold alerts.

## 2. Related Requirements

- FR-13 Species Suitability Guidance
- NFR-07 Reliability

## 3. Current Implementation

The tank workspace requests derived suitability for assigned species and shows:

- Suitable
- Needs attention
- Insufficient data / Unavailable

The service uses the latest reading selected by server `received_at` and the
Phase 02 90-second freshness window. Suitability evaluation now enumerates only
temperature, pH, and TDS. Legacy dissolved-oxygen storage remains available for
compatibility but does not participate in the evaluator. Ammonia has no active
species-care workflow and remains deferred.

## 4. Supported Parameters

The implemented suitability set is:

- temperature;
- pH;
- TDS.

Dissolved oxygen and ammonia are not supported suitability parameters for the
current product workflow. Legacy stored fields may remain for compatibility,
but they must not affect the approved status or user-facing result.

## 5. Reading and Freshness Rules

- Select the latest tank reading by server receipt time, not observation time.
- Use `received_at` for freshness with the 90-second Phase 02 window.
- Preserve the observation timestamp for historical and diagnostic display.
- A missing reading, stale reading, or missing current parameter value produces
  an unavailable check.
- A stale reading must never produce a confident Suitable result.

## 6. Preferred-Range Rules

- Exact minimum and maximum boundaries are within the preferred range.
- One-sided ranges are valid.
- Equal minimum and maximum values are valid.
- A current value below the configured minimum is Attention.
- A current value above the configured maximum is Attention.
- A missing range is shown as unavailable for that check.
- Species preferences do not consult or modify global operational thresholds.

## 7. Status Aggregation

For one species, only configured checks participate in the aggregate:

1. If any configured check is Attention, the species is Attention.
2. Otherwise, if any configured check is Unavailable, the species is
   Unavailable.
3. Otherwise, if at least one configured check exists, the species is Suitable.
4. If no supported check is configured, the species is Unavailable.

The tank summary applies the same precedence across assigned species. An empty
tank has status Unavailable with the reason `no_species_assigned`.

## 8. UI Behavior

The tank workspace shows the comparison reading, freshness context, overall
status, per-species status, configured ranges, current values, and human-readable
reasons. Users can filter the assigned species by All, Attention, Suitable, or
Unavailable. Deferred parameters are absent from the suitability response and
user-facing panel.

## 9. Backend and API Behavior

`GET /tanks/{tank_id}/species-suitability` returns a derived response with the
tank status, assigned-species results, per-check reasons, species counts, and a
reading freshness reference. The result is not persisted and does not create,
resolve, acknowledge, or reopen operational alerts.

The approved public species projection is documented in
`01-species-care-profiles.md`; suitability metadata remains staff-only.

## 10. Acceptance Criteria

- Exact preferred-range endpoints show Suitable.
- One-sided and equal-endpoint ranges evaluate correctly.
- A stale or missing reading shows Unavailable rather than Suitable.
- One out-of-range configured value produces Attention.
- Missing unconfigured ranges do not make an otherwise valid species fail.
- Dissolved oxygen and ammonia do not affect the approved suitability result.
- Suitability changes never create or resolve an operational alert.

## 11. Deferred Scope

- Dissolved oxygen and ammonia hardware, threshold, and suitability workflows.
- Per-species severity calibration beyond the current three statuses.
- Persisted suitability history or suitability alerts.
- Notification delivery or recommendation automation.

# Global Defaults and Tank Overrides

**Current implementation and Phase 02 hardening record — reviewed 2026-09-23.**

## 1. Purpose

Define the global fallback configuration and optional tank-specific threshold
sets used to evaluate incoming supported readings.

## 2. Current implementation

`ThresholdConfig` remains the global default for each parameter. Each tank
inherits that default unless it has a complete override for the parameter. An
override replaces the full set of warning/critical bounds and enabled state;
fields are not merged individually with the global row. Its unit is fixed from
the parameter's configured global unit and cannot be changed in the tank
workflow. Reset removes the override, so later global changes are inherited.

The current web configuration exposes temperature, pH, turbidity, and TDS.
Dissolved oxygen and ammonia remain supported internally and are hidden from
the current global and tank threshold workflows.

Each threshold may define warning and critical lower/upper bounds. One-sided
parameters may leave unsupported bounds empty. Two-sided configurations require
strict ordering of the supplied bounds:

```text
critical low < warning low < warning high < critical high
```

The decision engine uses open comparisons:

- values strictly below/above critical bounds are Critical;
- values strictly between a critical and warning bound are Warning;
- exact warning and critical boundary values remain Normal;
- values inside the warning range are Normal.

Global changes create a global historical revision. Tank override changes and
resets create tank-scoped revision events. Both apply prospectively to accepted
readings: configuration saves do not rewrite reading or alert history, recalculate
existing alerts, or reclassify the latest reading's displayed status. Status
projections resolve the thresholds that were effective at that reading's server
`received_at`. A later accepted reading applies the new effective threshold and
may transition the active alert.

The global and tank-threshold interfaces explain the strict/open semantics
before save: a value must pass a configured boundary to trigger Warning or
Critical, while exact warning and critical boundary values remain Normal. The
fields are presented as Critical below, Warning below, Warning above, and
Critical above.

## 3. Business rules

- **BR-001:** Each tank uses its full override when one exists for a parameter;
  otherwise it uses the current global default.
- **BR-002:** Newly saved global or tank thresholds apply prospectively to later
  readings; resets resume the global timeline.
- **BR-003:** Historical readings and alert history must not be silently
  rewritten or reclassified.
- **BR-004:** Invalid or non-strict bound ordering is rejected.
- **BR-005:** One-sided parameters may omit unsupported lower or upper bounds.
- **BR-006:** Disabled effective thresholds create no new alerts and expose the
  parameter as unavailable.
- **BR-007:** An active alert for a disabled parameter is resolved on the next
  usable reading with a system `threshold_disabled` reason; saving the setting
  alone does not change the alert.
- **BR-008:** Global and tank override writes are administrator-only and are
  recorded in the security audit stream.
- **BR-009:** No tank override is seeded, and assigned species preferences do
  not determine operational thresholds.
- **BR-010:** Public tank responses expose statuses calculated with the
  effective threshold but never expose numeric threshold configuration.

Analytics returns effective threshold history for a single selected tank. A
fleet or multi-tank view shows shared bands only when the selected tanks have
the same effective history; otherwise it explicitly reports that thresholds
vary by tank and omits the shared bands. There is no notification provider or
external delivery behavior in this phase.

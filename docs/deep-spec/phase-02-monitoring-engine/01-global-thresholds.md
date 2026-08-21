# Global Thresholds

**Current implementation and Phase 02 hardening record — reviewed 2026-08-21.**

## 1. Purpose

Define the global threshold configuration used to evaluate incoming supported
readings.

## 2. Current implementation

Thresholds are global across all tanks. The current web configuration exposes
temperature, pH, turbidity, and TDS. Dissolved oxygen and ammonia remain
nullable compatibility fields and are hidden from the current threshold
workflow.

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

Threshold changes create a historical revision and apply prospectively to the
next valid reading. Existing readings, analytics history, and active alerts are
not recalculated at save time.

## 3. Business rules

- **BR-001:** Newly saved thresholds apply to the next valid supported reading.
- **BR-002:** Historical readings and alert history must not be silently
  rewritten or reclassified.
- **BR-003:** Invalid or non-strict bound ordering is rejected.
- **BR-004:** One-sided parameters may omit unsupported lower or upper bounds.
- **BR-005:** Disabled thresholds create no new alerts and expose the parameter
  as unavailable.
- **BR-006:** An active alert for a disabled parameter is resolved on the next
  usable reading with a system `threshold_disabled` reason; saving the setting
  alone does not change the alert.
- **BR-007:** Threshold changes are administrator-only and are recorded in the
  security audit stream.

Per-tank threshold overrides are deferred. There is no notification provider or
external delivery behavior in this phase.


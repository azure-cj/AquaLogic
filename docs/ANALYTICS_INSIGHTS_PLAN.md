# Analytics Insights Plan (re-defense / exhibit)

Status: Goals 1–2 implemented locally; stopped for Claude backend review #1.
Goals 3–6 pending. Last reviewed: 2026-10-06.
Owner workflow: Codex implements each
goal on its own branch; Claude reviews the backend after Goal 2 and Goal 3 and
does the final UI polish after Goal 5.

This document is the **single source of truth** for the analytics insights work.
Part A is the shared contract (definitions, constants, algorithms, API schema,
UI copy). Part B contains paste-ready Codex goal prompts. Prompts reference
Part A instead of repeating it; if a prompt and Part A disagree, Part A wins.

---

## Part A — Shared contract

### A1. Purpose and principles

AquaLogic should answer, per tank and parameter: *Is it getting worse? How close
is the limit? Is this unusual? What could happen next?* — using transparent,
deterministic statistics. No machine learning.

Every output belongs to exactly one category, and the UI must label it:

| Category | Meaning | Examples |
|---|---|---|
| **Observed** | A stored measurement, unchanged except rounding | latest value, 30-min median points |
| **Derived** | A calculation over observed history | rate per hour, headroom, stability ratio, species compliance |
| **Projected** | A conditional extrapolation | boundary-crossing estimate, projection band |

Invariants (must hold in code and tests):

1. A projection is always phrased conditionally ("if the current trend
   continues") and never displayed as a measured value.
2. Projections and derived insights **never** create alerts, push
   notifications, or monitoring incidents. They are advisory and staff-only.
3. Trend, projection, and stability use observation time (`SensorReading.timestamp`).
   Freshness uses `received_at` via `app/services/reading_freshness.is_reading_current`.
4. If a tank has any non-mock reading inside an evaluation window, mock readings
   in that window are ignored. Otherwise mock readings are used. (No UI label
   distinguishes mock data.)
5. A window whose usable readings come from more than one source
   (`device_id`, `is_mock`) yields `insufficient_data` with reason `mixed_source`.
6. Every rule has an explicit insufficient-data state with a machine-readable
   `reason` and the counts that caused it. Never invent a value.
7. Turbidity gets trend, headroom and stability, but **no projection** and no
   species range.
8. Dissolved oxygen and ammonia stay out of scope.
9. Public endpoints are unchanged; nothing here is exposed publicly.

### A2. Constants (`app/services/current_insights.py`, module-level, exported)

| Name | Value | Notes |
|---|---|---|
| `METHOD_VERSION` | `"ci-v1"` | returned in responses |
| `BUCKET_SECONDS` | `1800` | 30-minute buckets, floor of UTC epoch |
| `MIN_BUCKET_READINGS` | `3` | readings with ≥3 distinct timestamps make a bucket qualify |
| `FIT_BUCKETS` | `12` | last 12 **complete** buckets = 6 h |
| `MIN_FIT_BUCKETS` | `10` | qualifying buckets required in the fit window |
| `MAX_GAP_SECONDS` | `3600` | max distance between consecutive qualifying bucket starts |
| `SLOPE_CI_Z` | `1.645` | 90% two-sided Sen slope interval |
| `BAND_Z` | `1.645` | residual band multiplier |
| `HORIZON_HOURS` | `3.0` | `min(3, fit_hours / 2)` |
| `PROJECTION_STEP_HOURS` | `0.25` | band and crossing resolution |
| `PROJECTED_PARAMETERS` | `("temperature", "ph", "tds")` | |
| `STABILITY_CURRENT_BUCKETS` | `48` | last 24 h of complete buckets |
| `STABILITY_MIN_CURRENT_BUCKETS` | `36` | |
| `BASELINE_DAYS` | `7` | the 7 days immediately before the current 24 h |
| `BASELINE_MIN_DAYS` | `5` | baseline UTC days with ≥24 qualifying buckets |
| `MORE_VARIABLE_RATIO` | `1.5` | |
| `STEADIER_RATIO` | `0.67` | |
| `SPREAD_FLOOR` | temperature `0.02`, ph `0.01`, tds `1.0`, turbidity `0.1` | divide by `max(baseline, floor)` |
| `SPECIES_COMPLIANCE_MIN_READINGS` | `30` | readings in last 24 h |
| Notable change (6 h) | temperature `0.5`, ph `0.15`, tds `max(20, 0.10·|median|)`, turbidity `max(2, 0.15·|median|)` | same values as `analytics_insights.py`; reuse, do not duplicate |

### A3. Algorithms

All computation is per (tank, parameter). `now` = evaluation time (injectable
for tests, default `datetime.now(timezone.utc)`).

**Buckets.** Floor observation timestamps to 30 min. A bucket is *complete* if
its end ≤ `now`. A bucket *qualifies* if it is complete and contains readings
with ≥3 distinct timestamps for that parameter (non-null, finite). Bucket value
= **median** of its readings. Bucket x-coordinate = bucket centre, in hours.

**B1 — Trend (Derived).**
1. Fit window = the last `FIT_BUCKETS` complete buckets.
2. Insufficient (`reason`): `too_few_buckets` (< `MIN_FIT_BUCKETS` qualifying),
   `gap` (consecutive qualifying starts > `MAX_GAP_SECONDS` apart),
   `not_recent` (most recent complete bucket does not qualify),
   `mixed_source`.
3. Theil–Sen slope `b` = median of `(y_j − y_i)/(x_j − x_i)` over all pairs `i<j`.
4. Slope interval: with `n` buckets, `N = n(n−1)/2`, sorted pairwise slopes
   `S[0..N−1]`, `C = SLOPE_CI_Z · sqrt(n(n−1)(2n+5)/18)`,
   `b_low = S[max(0, floor((N − C)/2))]`, `b_high = S[min(N−1, ceil((N + C)/2))]`.
5. Intercept `a` = median of `y_i − b·x_i`. Residuals `r_i = y_i − (a + b·x_i)`.
   `sigma = 1.4826 · median(|r_i − median(r)|)`.
6. `rate_per_hour = b`; `change_6h = b · 6`.
7. Status:
   - `rising` / `falling`: interval excludes zero (`b_low > 0` or `b_high < 0`)
     **and** `|change_6h| ≥ notable`.
   - `steady`: `|change_6h| < notable` **and** `(b_high − b_low)·6 < 2·notable`.
   - otherwise `uncertain`.

**B1 — Headroom (Derived).** Uses the latest observed value and the effective
**warning** bounds at `now` (`resolve_effective_thresholds`). Side chosen:
upper if trend is rising, lower if falling, otherwise the nearer bound.
`distance = upper − value` or `value − lower` (positive = inside).
`outside = distance < 0`. Missing bound on that side → `side_bound_missing`.
Disabled threshold → `null`.

**B2 — Species range (Derived).** Only temperature, pH, TDS. Use the species
assigned to the tank (`TankFish`) and their `ideal_*_min/max`.
`lo = max(non-null mins)`, `hi = min(non-null maxes)`.
- no species or all nulls → `not_configured`
- `lo > hi` → `conflict`, reporting the species that set `lo` and `hi`
- else `ok`, plus `compliance_percent_24h` = share of readings in the last 24 h
  (observation time) inside `[lo, hi]` inclusive, `null` if fewer than
  `SPECIES_COMPLIANCE_MIN_READINGS`; plus species headroom computed like B1
  headroom against `[lo, hi]`.
- turbidity → `not_applicable`.

**B3 — Projection (Projected).**
Preconditions, checked in order, each with its own status:
1. parameter not in `PROJECTED_PARAMETERS` → `not_applicable`
2. latest reading not current → `stale`
3. trend insufficient → `insufficient_data` (copy trend reason)
4. latest value outside warning bounds → `already_outside`
5. trend `steady` → `no_crossing_within_horizon` (still return the band)
6. trend `uncertain` → `too_uncertain`
7. warning bound missing on the trend side → `no_bound`

Band: origin `x_end` = end of the last fit bucket; `level = a + b·x_end`. For
`h = 0, 0.25, …, HORIZON_HOURS`:
`mid = level + b·h`, `low = level + b_low·h − BAND_Z·sigma`,
`high = level + b_high·h + BAND_Z·sigma`. Timestamps are `x_end + h`.

Crossing (rising, upper bound `U`; mirror for falling/lower):
- `mid_cross` = first `h` with `mid ≥ U`. If none within horizon →
  `no_crossing_within_horizon`.
- else `crossing_projected` with `crossing_hours_low` = first `h` with
  `high ≥ U`, `crossing_hours_high` = first `h` with `low ≥ U`, or `null`
  meaning "beyond the horizon".
Hours are measured from `now` (subtract `now − x_end`, floor at 0).

**B4 — Stability (Derived).**
- Spread = median of `|y_{k+1} − y_k|` over **adjacent** qualifying buckets
  (exactly 30 min apart). This is the "typical 30-minute change" and is not
  inflated by a slow drift.
- Current window: last `STABILITY_CURRENT_BUCKETS` complete buckets; needs
  `STABILITY_MIN_CURRENT_BUCKETS` qualifying (`insufficient_data`).
- Baseline: the `BASELINE_DAYS` days before the current window; needs
  `BASELINE_MIN_DAYS` UTC days with ≥24 qualifying buckets
  (`insufficient_baseline`, report `baseline_days_covered`).
- `ratio = current / max(baseline, SPREAD_FLOOR[parameter])`.
- `more_variable` if ratio ≥ 1.5, `steadier` if ≤ 0.67, else `typical`.
- Mixed source across current+baseline → `insufficient_data`, `mixed_source`.

**Attention items (Derived/Projected, for the Dashboard).** Built from all
evaluated tanks, ordered:
1. `projection.status == crossing_projected`, by `crossing_hours_low` ascending
2. `stability.status == more_variable`, by `ratio` descending
3. `species_range.status == conflict`
Return at most 10. Alerts and offline status are **not** included; the
Dashboard merges those from existing endpoints.

### A4. API

`GET /analytics/current-insights` — staff and admin (`require_staff`). Lives in
`app/routes/dashboard.py` next to `/analytics/fleet`. Schemas in
`app/schemas/analytics.py`. Service in `app/services/current_insights.py`.

Query: `tank_id` (repeatable, optional; max 20). Default = all active
(non-retired) tanks. Retired or unknown ids → 404 like other tank routes.
Independent of the Analytics range selector: it always describes *now*.

Performance: select only needed columns, one query per tank or a single
`IN` query over `now − (24 h + 7 d)` → `now`; stream rows; never load ORM
objects for readings.

Response (all floats rounded to 4 dp server-side; `null` allowed where shown):

```jsonc
{
  "evaluated_at": "2026-10-20T03:00:00Z",
  "method_version": "ci-v1",
  "constants": { "fit_hours": 6, "horizon_hours": 3, "baseline_days": 7, "bucket_minutes": 30 },
  "tanks": [{
    "tank_id": 3, "tank_name": "Calmwater Rack",
    "latest": { "observed_at": "…", "received_at": "…", "is_current": true },
    "parameters": [{
      "parameter": "temperature", "unit": "°C",
      "observed": { "value": 28.4, "observed_at": "…" },            // null if no reading
      "warning_bounds": { "min": 24.0, "max": 29.0 },               // null if disabled
      "critical_bounds": { "min": 22.0, "max": 31.0 },
      "trend": {
        "status": "rising",            // rising|falling|steady|uncertain|insufficient_data
        "reason": null,                // too_few_buckets|gap|not_recent|mixed_source
        "rate_per_hour": 0.18, "rate_ci_low": 0.12, "rate_ci_high": 0.24,
        "change_6h": 1.08, "notable_change": 0.5,
        "qualifying_buckets": 12, "required_buckets": 10,
        "fit_points": [{ "t": "…", "value": 27.3, "count": 60 }],   // bucket medians
        "fitted_start": { "t": "…", "value": 27.3 }, "fitted_end": { "t": "…", "value": 28.4 },
        "sigma": 0.05
      },
      "headroom": { "side": "upper", "bound": 29.0, "distance": 0.6, "outside": false, "reason": null },
      "species_range": {
        "status": "ok",                // ok|conflict|not_configured|not_applicable
        "min": 24.0, "max": 28.0, "species_count": 2,
        "conflict": null,              // {"min_species":"Discus","min":28.0,"max_species":"Corydoras","max":26.0}
        "compliance_percent_24h": 91.5, "headroom": { "side": "upper", "bound": 28.0, "distance": -0.4, "outside": true }
      },
      "projection": {
        "status": "crossing_projected", // crossing_projected|no_crossing_within_horizon|too_uncertain|stale|insufficient_data|already_outside|no_bound|not_applicable
        "reason": null,
        "bound_side": "upper", "bound": 29.0,
        "crossing_hours_low": 2.0, "crossing_hours_high": null,
        "horizon_hours": 3.0,
        "band": [{ "t": "…", "low": 28.3, "mid": 28.4, "high": 28.5 }]
      },
      "stability": {
        "status": "typical",           // more_variable|typical|steadier|insufficient_data|insufficient_baseline
        "reason": null,
        "current_spread": 0.04, "baseline_spread": 0.035, "ratio": 1.14,
        "current_buckets": 48, "baseline_days_covered": 7
      }
    }]
  }],
  "attention": [{ "tank_id": 3, "tank_name": "Calmwater Rack", "parameter": "temperature",
                  "kind": "projected", "type": "crossing_projected",
                  "crossing_hours_low": 2.0, "crossing_hours_high": null, "ratio": null }]
}
```

Web types mirror this in `web/src/features/analytics/types.ts` (`CurrentInsightsResponse`).
Document the endpoint in `docs/API_CONTRACT.md`.

### A5. UI copy (exact strings; Claude may refine wording during polish)

Category badges: `Observed`, `Derived`, `Projected`.

| State | Copy |
|---|---|
| trend rising/falling | `Rising {rate} {unit}/h over the last 6 h` / `Falling {rate} {unit}/h over the last 6 h` |
| trend steady | `Steady over the last 6 h` |
| trend uncertain | `No clear direction — readings vary` |
| trend insufficient | `Not enough recent readings ({qualifying} of {required} half-hour intervals)`; `gap` → `Recent readings have a gap over 1 hour`; `not_recent` → `No readings in the last half hour`; `mixed_source` → `Readings come from more than one source` |
| headroom inside | `{distance} {unit} from the {upper\|lower} warning bound ({bound} {unit})` |
| headroom outside | `Outside the warning range` |
| projection crossing | `If the current trend continues, may reach the {upper\|lower} warning bound ({bound} {unit}) in about {low}–{high} h` ; if high is null: `… in about {low} h or later` |
| projection none | `Not projected to reach a warning bound within 3 h if the trend continues` |
| projection too_uncertain | `Trend too uncertain to project` |
| projection stale | `No projection: the latest reading is not current` |
| projection insufficient | `No projection: not enough recent readings` |
| projection already_outside | `Already outside the warning range — see alerts` |
| projection no_bound | `No warning bound configured on this side` |
| projection not_applicable | `Turbidity is not projected because it changes in sudden events` |
| stability more_variable | `More variable than usual ({ratio}× its 7-day baseline)` |
| stability typical | `Typical variability for this tank` |
| stability steadier | `Steadier than usual ({ratio}× its 7-day baseline)` |
| stability insufficient_baseline | `Baseline needs 5 days of readings ({days} available)` |
| stability insufficient_data | `Not enough readings in the last 24 h` |
| species ok | `{pct}% of the last 24 h within the assigned species' range ({min}–{max} {unit})` |
| species conflict | `Assigned species' ranges do not overlap: {min_species} needs at least {min}, {max_species} needs at most {max}` |
| species not_configured | `No species range configured` |

Display rounding: crossing hours to nearest 0.5 h; rates to 2 significant
decimals; ratios to 1 dp.

"How is this calculated?" disclosure text (one per category):
- Derived trend: `Theil–Sen robust slope over the last 6 h of 30-minute medians. Requires 10 of 12 intervals. Robust to occasional sensor spikes.`
- Projected: `Extends the 6 h trend up to 3 h, using the 90% slope range plus typical reading scatter. Shown only when the trend is clear and the latest reading is current. Not a measurement.`
- Stability: `Compares the typical 30-minute change over the last 24 h with the same measure over the previous 7 days for this tank.`
- Species: `Overlap of the configured preferred ranges of all species assigned to this tank.`

### A6. Demo scenarios (B6)

Seeded demo tanks must show each insight reliably at **any** time of day,
including after the seed was run hours earlier. Therefore seed history and the
live demo sensor must use one shared deterministic function
`scenario_value(tank_code, parameter, t)` so live readings continue the seeded
curves with no discontinuity.

| Role | Behaviour | Must produce |
|---|---|---|
| Stable | small daily temperature cycle (±0.3 °C), tiny noise | trend `steady`, stability `typical`, species `ok` |
| Warming | repeating 8 h sawtooth: ~6.5 h slow warm-up from mid-range toward/just past the upper warning bound, ~1.5 h cool-down | `crossing_projected` for ≥60% of wall-clock times |
| Unstable pH | normal for 7+ days, pH noise ~2.5× larger in the last 24 h *rolling* (implement as variability that depends on a long cycle so it is always "recent") | stability `more_variable` for ≥80% of times |
| Species conflict | assigned species whose configured temperature ranges do not overlap (use existing `seed_fish` values, e.g. a warm-water and a cool-water species) | species `conflict` |
| Short / offline | existing offline service tank (no live readings) | `stale` / insufficient states |

Values must stay physically plausible: temperature 22–31 °C, pH 6.4–8.2, TDS
80–450 ppm, turbidity 0–25 NTU; max 0.2 °C change between consecutive 30 s
readings except turbidity spikes. TDS drifts upward slowly (evaporation) with
a reset every few days (water change). Use a fixed RNG seed or hash-based
noise so results are reproducible.

**Safety rule:** the demo sensor writes **only** to tanks listed in the
scenario map by `tank_code`, and never to a tank that has an active
`RegisteredDevice`. The real hardware tank at the exhibit must receive only
real readings.

---

## Part B — Codex goal prompts

Workflow: run one goal at a time, each on its own branch from `main`. After a
goal finishes, run its acceptance commands yourself, then continue. **Stop at
the review checkpoints** and ask Claude to review the branch diff before the
next goal.

| Goal | Contents | Branch | Checkpoint after |
|---|---|---|---|
| 1 | B0 docs + B1 trend/headroom + B2 species range + endpoint | `feat/current-insights-core` | — |
| 2 | B3 projection + attention items | `feat/current-insights-projection` | **Claude review #1** |
| 3 | B4 stability + B6 demo scenarios | `feat/current-insights-stability-demo` | **Claude review #2** |
| 4 | U1 + U2 Analytics "Tank insights" structure and chart | `feat/analytics-tank-insights-ui` | — |
| 5 | U3 Dashboard "Needs attention" | `feat/dashboard-needs-attention` | **Claude polish** |
| 6 (optional) | B5 backtest on real hardware data | `feat/current-insights-backtest` | — |

### Rules shared by every goal (included in each prompt)

```text
SHARED RULES
- Read AGENTS.md, CLAUDE.md and docs/ANALYTICS_INSIGHTS_PLAN.md (Part A is binding) before coding.
- Create the branch named in this goal from main. Commit with conventional prefixes (feat:/fix:/docs:/test:), staging specific files only (never `git add .`). Do not push and do not open a PR.
- Do not change: auth, actuator/command code, bridge/, mobile_app/, firmware, Alembic migrations, public tank endpoints, alert/decision engine behavior, or existing response fields of /analytics/fleet.
- No new dependencies (backend or web). No machine learning. No schema/migration changes.
- Projections and insights must never create alerts, push events or incidents.
- You may be running unattended. Do not stop for ambiguity: choose the most conservative interpretation consistent with Part A, continue, and record each decision in an "Assumptions" list in your final message. Stop early only if a change would violate the "Do not change" list or need a migration or new dependency.
- If tests fail, fix the code. Never delete, skip, or weaken existing tests. If the same failure persists after 3 attempts, record it under "Unresolved" and continue with the remaining tasks.
- If the previous goal's branch is not merged into main, branch from the previous goal's branch and say so.
- Respect every STOP marker: do not start a later goal past a STOP.
- Finish with: per-goal summary, branch name, files touched, test commands run with results, Assumptions, Unresolved, and any deviations from Part A.
```

### Paste-ready run prompts

Each run stops at a review checkpoint. Paste one run at a time; the goal
details are in the sections below and are read from this file.

**Run 1 (Goals 1 + 2, overnight-safe):**

```text
Run Goal 1 and then Goal 2 from docs/ANALYTICS_INSIGHTS_PLAN.md Part B, in order. Follow Part A and the SHARED RULES in Part B. Stop after Goal 2 (review checkpoint).
```

**Run 2 (Goal 3), after Claude review #1 is addressed:**

```text
Run Goal 3 from docs/ANALYTICS_INSIGHTS_PLAN.md Part B. Follow Part A and the SHARED RULES in Part B. Stop after Goal 3 (review checkpoint).
```

**Run 3 (Goals 4 + 5), after Claude review #2 is addressed:**

```text
Run Goal 4 and then Goal 5 from docs/ANALYTICS_INSIGHTS_PLAN.md Part B, in order. Follow Part A and the SHARED RULES in Part B. Structure only — no visual design. Stop after Goal 5 (polish checkpoint).
```

**Run 4 (optional Goal 6)**, only after the real hardware tank has logged several days:

```text
Run Goal 6 from docs/ANALYTICS_INSIGHTS_PLAN.md Part B. Follow Part A and the SHARED RULES in Part B.
```

### Goal 1 — Core current insights (B0 + B1 + B2)

```text
GOAL 1: Core current insights backend (trend, headroom, species range).
Branch: feat/current-insights-core

Follow the "SHARED RULES" block in docs/ANALYTICS_INSIGHTS_PLAN.md Part B (binding).

Tasks:
1. Docs (B0):
   - Add a dated entry to docs/DECISIONS.md: "Bounded, advisory current insights and short-horizon projections" — supersedes the "predictive analytics deferred" note only for the bounded, conditional, staff-only projections defined in docs/ANALYTICS_INSIGHTS_PLAN.md; no ML; never alerts.
   - Fix the documentation mismatch: the 2026-08-21 decision says analytics buckets water quality on received_at, but code buckets water-quality trends on observation timestamp (and CLAUDE.md agrees). Add a correcting note in a new dated DECISIONS entry (do not rewrite the old entry).
2. Create app/services/current_insights.py with the constants in Part A §A2 (reuse the notable-change values from analytics_insights.py by importing or extracting a shared helper; do not duplicate magic numbers).
3. Implement Part A §A3 B1 (buckets, Theil–Sen trend with slope interval, sigma, status) and B1 headroom, and B2 species range, exactly as specified, including invariants 3–6 in §A1.
4. Add GET /analytics/current-insights per §A4 with Pydantic schemas in app/schemas/analytics.py. For this goal, return `projection` with status "not_applicable" for turbidity and "insufficient_data" with reason "not_implemented" for others, `stability` with status "insufficient_data" reason "not_implemented", and `attention: []`. Goal 2/3 fill these in.
5. Make `now` injectable in the service for tests.
6. Tests in backend/tests/test_current_insights.py (use existing conftest fixtures; insert readings directly):
   - Theil–Sen: known slope recovered on clean linear data; single extreme spike does not flip status; slope interval indices match the formula for n=10 and n=12.
   - Trend statuses: rising, falling, steady, uncertain (noisy oscillation), each insufficient reason (too_few_buckets, gap, not_recent, mixed_source).
   - Mock rule: mock readings ignored when real readings exist in window; used otherwise.
   - Bucket qualification requires 3 distinct timestamps; partial current bucket excluded.
   - Headroom: side selection by trend; outside; disabled threshold → null; tank override respected.
   - Species: ok with compliance, conflict names correct species, not_configured, turbidity not_applicable, compliance null under 30 readings.
   - Endpoint: staff allowed, unauthenticated 401, retired tank 404, >20 ids 422, default returns active tanks only.
7. Update docs/API_CONTRACT.md (new endpoint), docs/areas/BACKEND.md (service summary), docs/DEVELOPMENT_STATUS.md.

Acceptance (from backend/): `pytest -q` all green.
```

### Goal 2 — Projection and attention (B3)

```text
GOAL 2: Short-horizon projection and attention items.
Branch: feat/current-insights-projection (from main after Goal 1 is merged; if not merged, branch from feat/current-insights-core and say so)

Follow the "SHARED RULES" block in docs/ANALYTICS_INSIGHTS_PLAN.md Part B (binding).

Tasks:
1. Implement Part A §A3 B3 exactly: precondition order and statuses, band generation at 0.25 h steps to 3 h, crossing rule (mid must cross within horizon; low/high from band edges; null high = beyond horizon), hours measured from `now`.
2. Implement attention items per §A3 (projection crossings first by crossing_hours_low, then more_variable by ratio — stability is still "not_implemented" so that group is empty for now — then species conflicts). Max 10.
3. Tests in backend/tests/test_current_insights.py:
   - Each precondition status (not_applicable, stale, insufficient_data, already_outside, steady→no_crossing with band present, too_uncertain, no_bound).
   - Rising series approaching upper bound → crossing_projected with low ≤ mid-cross ≤ high (or high null).
   - Falling series approaching lower bound (mirror).
   - Rising series far from bound → no_crossing_within_horizon.
   - Band: length 13, low ≤ mid ≤ high everywhere, widens with h.
   - Stale latest reading (received_at older than 90 s) blocks projection even with a perfect trend.
   - Projection never creates Alert, PushNotificationEvent or MonitoringIncident rows (assert counts unchanged after calling the endpoint).
   - Attention ordering.
4. Update docs/API_CONTRACT.md and docs/DEVELOPMENT_STATUS.md.

Acceptance (from backend/): `pytest -q` all green.

STOP after this goal: the owner will ask Claude to review the backend diff before Goal 3.
```

### Goal 3 — Stability and demo scenarios (B4 + B6)

```text
GOAL 3: Stability vs own baseline, and deterministic demo scenarios.
Branch: feat/current-insights-stability-demo

Follow the "SHARED RULES" block in docs/ANALYTICS_INSIGHTS_PLAN.md Part B (binding).

Tasks:
1. Implement Part A §A3 B4 stability exactly (adjacent-bucket median absolute change, current 24 h vs previous 7 days, min coverage, spread floor, ratio labels) and enable the more_variable attention group.
2. Demo scenarios per Part A §A6:
   - Create backend/seed/demo_scenarios.py with a pure deterministic function scenario_value(tank_code, parameter, t) and a SCENARIOS map from tank_code to role. Map roles onto the existing demo tanks from seed/seed_tanks.py and seed/seed_dashboard_demo.py; keep the existing "Recovery Reef"/SERVICE-01 offline behavior and the existing latest normal/warning/critical states expected by tests/test_demo_seed.py (update that test only if a state must change, and explain why).
   - Pick the species-conflict tank using existing seed_fish ranges; report which species and ranges you used. Do not edit species ranges unless no existing pair conflicts.
   - Extend seeded history to 14 days (DEMO_HISTORY_DAYS) at the existing 30 s cadence using scenario_value, with bulk inserts; keep seeding idempotent.
   - Change app/services/demo_sensor.py so live readings come from scenario_value for tanks in SCENARIOS only, and it NEVER writes to a tank that has an active RegisteredDevice or is not in SCENARIOS. Keep is_mock=True.
3. Tests:
   - Stability: more_variable, typical, steadier, insufficient_data, insufficient_baseline (with baseline_days_covered), spread floor, slow drift does not produce more_variable.
   - Demo: scenario_value is deterministic and continuous (no jump > plausibility limit between t and t+30 s); value ranges plausible.
   - Demo sensor safety: a tank with an active device and a tank not in SCENARIOS receive no demo readings.
   - Scenario reliability: evaluate current insights over the seeded data at 24 evenly spaced "now" values across a day and assert the role targets in §A6 (warming ≥60% crossing_projected, unstable pH ≥80% more_variable, stable tank steady/typical, conflict tank conflict). Use a reduced history window if needed for test speed, but keep the same functions.
4. Update docs/DEVELOPMENT_STATUS.md, docs/areas/BACKEND.md, and the seed section of docs that describe demo data.

Acceptance (from backend/): `pytest -q` all green; `python -m seed.seed_data` runs on a fresh local SQLite DB.

STOP after this goal: Claude review #2 before UI work.
```

### Goal 4 — Analytics "Tank insights" UI structure (U1 + U2)

```text
GOAL 4: Analytics page "Tank insights" section — STRUCTURE ONLY.
Branch: feat/analytics-tank-insights-ui

Follow the "SHARED RULES" block in docs/ANALYTICS_INSIGHTS_PLAN.md Part B (binding).

Important: you are building the structural foundation. A designer will do the
visual polish afterwards. Do NOT invent visual design: no new colors, gradients,
shadows, animations, icons beyond existing lucide usage, or custom fonts. Use
existing components from @/shared/components/admin-ui (Panel, EmptyState,
LoadingState, etc.), existing semantic CSS tokens, and plain grid/flex layout.
Keep new CSS minimal and in web/src/features/analytics/styles.css under a
clearly marked `/* tank-insights (structure, to be polished) */` block, using
only existing tokens; if a token is missing, use the closest existing one and
leave a `/* TODO polish */` comment. Use the exact copy in Part A §A5.

Tasks:
1. Types: add CurrentInsightsResponse and nested types to web/src/features/analytics/types.ts mirroring Part A §A4 exactly.
2. Data: a react-query hook useCurrentInsights(tankId) calling GET /analytics/current-insights?tank_id=… via the shared api client. Refetch on window focus only; no polling interval.
3. New component folder web/src/features/analytics/tank-insights/:
   - TankInsightsSection.tsx: placed at the TOP of AnalyticsPage, above the existing controls. Has its own single-tank <select> (default: first tank in the response's attention list, else first active tank). Independent of the existing range/scope controls. The existing page content below is kept unchanged and gets a section heading "History".
   - ParameterSummaryCard.tsx: one per parameter (temperature, pH, turbidity, TDS) in a responsive grid. Inside each card three labeled blocks, in this order, each with a text badge: Observed (latest value, unit, observed time, "not current" note when latest.is_current is false), Derived (trend line of copy, headroom copy, stability copy, species copy), Projected (projection copy). Clicking a card selects it for the chart.
   - MethodDisclosure.tsx: a <details> "How is this calculated?" with the §A5 disclosure texts.
   - CopyFormatter.ts: pure functions mapping API states to §A5 strings (including rounding rules). Unit-test every state.
   - RecentTrendChart.tsx (Recharts, already a dependency): for the selected parameter shows, on one time axis from first fit point to the end of the projection band:
       * Observed: fit_points as a solid line with dots, legend "Observed (30-min median)".
       * Derived: fitted_start→fitted_end as a dashed line, legend "Trend (last 6 h)".
       * Projected: band as a shaded Area between low/high plus mid as a dotted line, legend "Projection if trend continues"; only rendered when band is non-empty.
       * A vertical ReferenceLine labeled "Now" at evaluated_at.
       * Warning bounds as ReferenceLines/ReferenceArea like the existing chart; species range (status ok) as a separate ReferenceArea with legend "Species range".
       * Tooltip: label each value with its category ("Observed", "Trend", "Projected low/mid/high"); never show a projected value without the word "Projected".
       * Turbidity or empty band: no projection layer, show projection copy under the chart.
   - All insufficient/stale/conflict states render their §A5 copy; never hide a card because data is missing.
4. Accessibility: section has a heading; badges are text (not color only); chart has an aria-label summarizing the trend copy.
5. Tests (vitest + testing-library), mocking the API:
   - CopyFormatter: every status for trend, headroom, projection, stability, species.
   - Section renders 4 cards, default tank selection rule, tank switch refetches.
   - Projected block always contains the word "If the current trend continues" for crossing_projected.
   - Chart renders projection layer only when band present; turbidity shows not_applicable copy.
   - Existing AnalyticsPage tests still pass.
6. Update docs/areas/WEB.md and docs/DEVELOPMENT_STATUS.md.

Acceptance (from web/): `npm run typecheck`, `npm test`, `npm run build` all pass.
```

### Goal 5 — Dashboard "Needs attention" (U3)

```text
GOAL 5: Fleet dashboard "Needs attention" panel — STRUCTURE ONLY.
Branch: feat/dashboard-needs-attention

Follow the "SHARED RULES" block in docs/ANALYTICS_INSIGHTS_PLAN.md Part B (binding).

Same visual restrictions as Goal 4 (structure only, existing components/tokens, minimal CSS in web/src/features/fleet/styles.css under `/* needs-attention (structure, to be polished) */`). Reuse CopyFormatter from Goal 4.

Tasks:
1. In web/src/features/fleet/FleetPage.tsx add a NeedsAttentionPanel at the top of the page content (below the page header and status counts, above "Tank health").
2. Data: existing /fleet response (critical/offline tanks, open alerts) + GET /analytics/current-insights (no tank_id) attention list.
3. Ranking, max 3 rows total:
   a. Observed: tanks with status critical, then offline (from /fleet), badge "Observed".
   b. Projected: attention items of kind "projected" (projection copy, shortened to "{tank} · {parameter}: may reach warning bound in about {low}–{high} h if trend continues"), badge "Projected".
   c. Derived: more_variable then species conflict, badge "Derived".
   Each row links to /admin/analytics with the tank preselected in the Tank insights section (support a `?insights_tank=<id>` query param in Goal 4's section; add it here if missing).
4. Empty state: "No tanks need attention right now." plus, if any tank's trend is insufficient_data, a second line "{n} tanks have too little recent data to assess."
5. If current-insights fails to load, still render observed rows and show "Insights unavailable" — do not block the dashboard.
6. Tank cards: add a small trend indicator next to temperature and pH only when that parameter's trend status is rising/falling (arrow + "{rate} {unit}/h"); nothing otherwise.
7. Tests: ranking and 3-row cap, empty state with insufficient count, insights error fallback, link carries insights_tank, trend indicator only for rising/falling. Existing FleetPage tests pass.
8. Update docs/areas/WEB.md and docs/DEVELOPMENT_STATUS.md.

Acceptance (from web/): `npm run typecheck`, `npm test`, `npm run build` all pass.

STOP: the owner will ask Claude for the UI polish pass.
```

### Goal 6 (optional) — Backtest on real hardware data (B5)

Run only after the real hardware tank has logged several days of readings.

```text
GOAL 6: Projection backtest CLI.
Branch: feat/current-insights-backtest

Follow the "SHARED RULES" block in docs/ANALYTICS_INSIGHTS_PLAN.md Part B (binding).

Tasks:
1. Add backend/app/cli/backtest_projections.py runnable as `python -m app.cli.backtest_projections --tank-id N --days D [--exclude-mock]`.
2. For every 30-minute step `t` in the history (where a projection can be computed using only readings observed before `t`), compute the projection with now=t using the same service functions, then compare with the actual 30-minute medians at t+0.5 h … t+3 h.
3. Report (stdout table + optional --json): number of projections by status; band coverage (share of actual medians inside [low, high]) per horizon; for crossing_projected: share where an actual crossing occurred within 3 h (precision); for actual crossings: share preceded by a crossing_projected within the prior 3 h (recall); median absolute error of mid per horizon.
4. Read-only: the CLI must not write to the database.
5. Tests with a small synthetic history verifying metrics on a known linear case.
6. Document usage in docs/areas/BACKEND.md.

Acceptance: `pytest -q` green.
```

# M2/M3 operator context and Analytics interpretation

Status: Implemented locally; production and physical-device checks remain separate.
Last reviewed: 2026-10-02

## Preserved baseline and Analytics reconciliation

Work continues on `fix/pump-controls-ux-copy` over the uncommitted M0/M1 and
unrelated changes recorded in [M0/M1](M0_M1_OPERATOR_GUIDANCE.md). No checkout
replacement, cherry-pick, commit, migration, deployment, production-setting
change, firmware or bridge change was performed.

Compared `a035e44c1f87765712506c90c7f651d191cdc4ec` and its parent, then applied
only its completed Analytics service/schema/page/types/utils/styles and web
test delta. Manually reconciled the backend Analytics test hunks against the
older file, retaining its existing tests and changes. This restores fixed UTC
half-hour observation buckets (:00/:30 in Manila), partial graph intervals,
interval tooltips, contributor wording, CSV mapping, manual Refresh and last
successful update. Reporting and alert resolutions remain independent;
reporting follows receipt time, metrics follow observation time. Selected tanks
remain overlays; fleet statistics retain fleet scope. No Analytics redesign.

M1's Analytics action is enabled using `tanks` and `metric`. ISO custom window
URLs now populate local datetime controls without shifting their API interval.

## M2 species context

`GET /alerts/{id}/context` adds optional `species_context`. It identifies the
parameter, `basis=current_assignments_latest_reading`, latest received reading
ID/observation/receipt times, available/unavailable/unsupported status and
reason, distinct assigned/evaluable/within/outside/unavailable counts,
individual species IDs/names/stored lower and upper preferences/results/reasons,
unit and advisory. It uses current assignments and preferences even for a
historical or retired-tank alert. No population count, averaged species range,
new threshold, alert, push, or persistence is introduced.

Temperature, pH and TDS reuse `species_suitability.evaluate_check`, with
inclusive and one-sided boundaries. Missing, inverted or non-finite ranges
are unavailable. Turbidity is explicitly unsupported. Stored bounds remain
visible when comparison is unavailable. The supplementary display gate requires
both receipt and observation age <=90 seconds and an observation no more than
five seconds ahead of evaluation time. Five seconds tolerates minor sensor
clock skew; larger future observations are unavailable. Missing/non-finite
values are unavailable. This gate does not change operational receipt freshness
or the existing suitability endpoint/status engine. Per-species missing/invalid
preferences take precedence over a reading gate in row reasons.

Web drawer and Flutter detail show counts, expandable individual preferences,
basis/timestamps/reasons and the exact advisory: “Stored species preferences
provide additional context. AquaLogic alerts continue to use the tank's
configured thresholds.” Older responses with no field remain readable. Flutter
uses typed optional DTO/domain objects, validates present additive data and
keeps its existing mock context explicitly unavailable/demo.

## M3 historical interpretation

The additive `decision_support_insights` response has typed cards plus explicit
limitations and an advisory. The reusable `analytics_insights` accumulator
receives the existing streamed observations, after one batch effective-threshold
history lookup. It keeps per-tank/parameter half-hour sums/counts, at most three
distinct timestamp witnesses per interval, first/last timestamps and bounded
history/source states. It makes no history query per observation and stores no
raw observation series for inference. Existing Analytics fields/calculations
are retained. No inference is made from a changing fleet average.

Cards have stable `<tank>.<parameter>.<rule>.v1` IDs, named tank scope/ID,
parameter/title/explanation, selected window and observation interval,
sample count, evidence, qualifications, optional shared M1 checks and real
related alert IDs. Findings cover only increasing/decreasing observations,
little sustained change, percentage of observations within operating bounds,
and repeated alert records. There are no proactive warnings, variability
rankings, scores, recovery claims or forecasts. M3 is web-only.

Deterministic order is within-range cards from lowest percentage, repeated
records from highest count, directions, then little change. Ties use tank name,
tank ID, metric order temperature/pH/turbidity/TDS, then rule. Four cards are
visible initially; accessible expansion shows the remainder. Limitations are
expandable. Graph actions select the named tank/metric and retain the window.
Related records use tank/parameter/creation-window filters or M1 `alert_id`.
Absent additive response fields hide the section for staged rollout.

### Engineering heuristics (not safety limits)

- Notable change E: temperature 0.5°C, pH 0.15 units, turbidity the greater of
  2 NTU or 15% of the period median of interval averages, TDS the greater of
  20 ppm or 10% of that median. No pH percentage change is introduced.
- Direction/little-change evidence needs >=30 usable observations spanning
  >=3 hours, >=7 qualifying completed half-hours with >=3 distinct observation
  timestamps each, and >=80% coverage of fully contained completed intervals
  in the selected window. Completed means ending no later than the window end
  or evaluation time. Partial intervals remain in the graph and are excluded
  from inference. No interpolation occurs.
- A substantial gap is >60 minutes between qualifying interval starts (two
  consecutive missing half-hours). Any device-ID or mock/source-mode change
  across completed observations suppresses inference, including transitions
  to/from an unknown source. These are explicit limitation reasons.
- Use existing per-tank half-hour averages, median first floor(n/3) versus last
  floor(n/3), and ordinary least-squares slope over actual interval timestamps.
  Fitted change is slope times the observed interval-start span. Increasing or
  decreasing needs both changes >E in the same direction; both signs must
  survive removing either endpoint interval. To suppress noisy apparent
  directions, fitted residual P90–P10 must also be <=2E.
- Little change needs both absolute changes <E and interval-average P90–P10
  <=2E (linearly interpolated percentile). Sparse/noisy/inconsistent evidence
  yields limitations, never a stable finding. Little change outside configured
  bounds still has its separate abnormal within-range proportion.
- Within range requires >=30 evaluable observations spanning >=1 hour.
  Compare observation-time values with tank warning operating bounds effective
  at observation time. Endpoints are inclusive; one-sided bounds work. Missing,
  disabled, unconfigured or invalid bounds/values are excluded and counted.
  This is percentage of observations, never percentage of time or health.
  Threshold-state changes are disclosed; expanded bounds are not improvement.
  The operational evaluator's strict/exact-critical-edge behavior is untouched.
- Repeated records require >=3 distinct alert IDs created in the selected
  [start,end) window for one tank/parameter. The wording counts records; operator
  handling with continued abnormal readings may create further records and
  does not establish independent physical episodes.
- Delayed observations can contribute qualified historical evidence; no live
  forecast is made. Qualifications disclose delayed counts and changed bounds.

## Review and release boundaries

See [isolated review runbook](M2_M3_REVIEW_RUNBOOK.md) for commands, credentials,
scenario expectations and production smoke checks. The launcher is separate
from start-dev/classroom workflows. Its ignored dedicated SQLite/media and
synthetic accounts are opt-in only; production PostgreSQL requirements and
Vercel `/api` Railway rewrite remain unchanged.

A separate disposable PostgreSQL 18 cluster was initialized on loopback port
55432 using the installed tools outside PATH. One opt-in integration case passed
real admin/staff login, current/stale species context, streamed interpretation,
observation-time tank overrides, recurrence, retired context and handling guards.
Full model metadata was created in an empty dedicated test database and removed
after the check; the temporary cluster was stopped. The existing PostgreSQL
service was untouched. Production Railway remains untested.
Physical Android push-tap verification from M1 remains pending. No production
credentials, accounts, data or hardware were used.

Validation results are recorded in DEVELOPMENT_STATUS and the final handoff.

## Validation checkpoint

Full SQLite backend suite: 277 passed with the existing Firebase Message.token
deprecation warning; a separate PostgreSQL 18 integration test also passed. Full web: 131 passed; typecheck and production build passed. Full
Flutter: 205 passed; analysis reported no issues. A final threshold-history
qualification refinement passed all 30 focused Analytics cases after the full
backend run. Query-count coverage confirms the number of SQL queries remains
constant when the observation volume increases tenfold.

Actual loopback API scenarios were checked as admin and staff against computed
manifest evidence (UTC string formats normalized), including retired context.
Fresh-reset checks verified mixed species, unsupported turbidity, missing
preferences, delayed observation and stale receipt. Startup/stop/reset/restart,
scenario-index delivery and blocked hardware/push writes were verified. Browser
checks used the real API at desktop and 320px widths; no document horizontal
overflow at 320px. Screenshots: m3-analytics-desktop.png,
m3-analytics-narrow.png and m2-species-narrow.png under
`docs/evidence/operator-guidance/`. Flutter narrow species expansion is covered
by its widget test. Local diff/whitespace and source syntax checks passed.

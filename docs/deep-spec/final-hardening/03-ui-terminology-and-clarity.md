# Monitoring and Species-Care UI Clarity

Classification: **Polish/harden now**  
Status: Implemented UI clarity hardening; algorithms unchanged  
Last reviewed: 2026-08-22

## Objective

Remove misleading implications from otherwise sound monitoring behavior. This
packet changes presentation and terminology, not the threshold, freshness,
alert, or Species Care engines.

## Shared invariants

- Freshness remains based on server `received_at` with a 90-second window.
- Stale readings remain visible as historical/last-known context.
- Stale data must not look like a current Normal measurement.
- Manual alert handling remains distinct from system-confirmed recovery.
- Global thresholds continue to drive operational status and alerts.
- Species preferences remain advisory and do not modify thresholds or alerts.
- Species Care continues to evaluate temperature, pH, and TDS only.
- Threshold comparisons remain strict/open; exact configured boundaries remain
  Normal.
- Historical readings and alerts are never reclassified by copy changes.

## Work item A — last-known offline data

### Current seam

The fleet API already exposes `reporting_age_seconds`, but the fleet table
renders `latest_reading` values without changing their labels when tank status
is Offline. The tank operations response exposes the latest reading and an
evaluated status but does not include reporting age directly. Tank detail uses
headings such as “Latest reading” and “Current readings” even when the derived
status is Offline.

### Required behavior

When status is Offline or the reading is otherwise stale:

- use “Last known temperature”, “Last known pH”, or “Last known readings” in
  headings/accessible labels where the UI could imply currency;
- retain the values rather than hiding them;
- show reporting age in human language when available, for example “No report
  for approximately 13 hours”;
- keep observation time separately identified when it is shown;
- avoid using only observation timestamp to determine or explain freshness.

For current data, existing concise labels may remain. Missing data should remain
Unavailable/No reading rather than “last known” with an empty value.

### API decision for implementation planning

Prefer a shared formatting helper for `reporting_age_seconds`. If tank detail
needs the age and cannot derive it reliably from `received_at` because that
field is absent from its public type, add the minimal authenticated operations
response field rather than using observation `timestamp`. Any API addition must
be documented in `docs/API_CONTRACT.md` and covered by a response-model test.

Likely web touchpoints:

- `web/src/features/fleet/FleetPage.tsx`
- `web/src/features/tanks/TankDetailPage.tsx`
- shared formatting utilities and their tests
- relevant fleet/tank component tests

## Work item B — manual alert terminology

### Current semantics

`PUT /alerts/{alert_id}/resolve` closes the persistent alert record, records the
operator and `resolution_source = operator`, and removes it from unresolved
queues. It does not require a fresh Normal reading. A later fresh Normal reading
uses system resolution; a later abnormal reading after manual closure creates a
new incident.

### Required UI terminology

Rename the operator-facing action:

```text
Resolve -> Mark handled
Resolving… -> Marking handled…
Alert marked as resolved. -> Alert marked as handled.
Resolved by operator -> Handled by operator
```

Add concise explanatory text at the action or confirmation boundary:

> Marks this alert as handled and removes it from the active queue. This does
> not confirm that water conditions have recovered. A later abnormal reading
> may create another alert.

Automatic history wording should continue to communicate recovery, for example
“Automatically resolved” or “Recovered automatically,” only when the existing
system-resolution semantics support it.

### Compatibility boundary

The backend route and stored `is_resolved`/`resolution_source` fields may remain
unchanged to avoid unnecessary API churn. This is primarily a UI terminology
change. Update canonical API prose to distinguish the legacy route name from
the user-facing “Mark handled” action.

Likely touchpoints:

- `web/src/features/alerts/AlertsPage.tsx`
- `web/src/features/tanks/TankDetailPage.tsx`
- their tests
- `docs/API_CONTRACT.md`
- `docs/deep-spec/phase-02-monitoring-engine/05-alert-lifecycle.md`

## Work item C — operational status versus Species Care

Both results can legitimately differ:

```text
Operational status: Normal
Species Care: Needs attention
```

Required help text near the tank-level presentation:

> Operational status uses global monitoring thresholds. Species Care compares
> current supported readings with assigned-species preferences.

Do not merge statuses, recolor one to pretend it is the other, change global
thresholds per species, or create Species Care alerts.

Component tests must render a Normal operational result beside an Attention
Species Care result and assert that the explanation is visible or accessible.

## Work item D — Species Care water-only scope

Required scope explanation near Species Care:

> Species Care evaluates supported water conditions only. It does not assess
> fish-to-fish compatibility, stocking density, temperament, or breeding
> behavior.

Where it improves clarity without crowding the UI, prefer:

- “Water suitable” instead of “Suitable”;
- “Within preferred water range” instead of a broad suitability claim;
- “Current reading” only when freshness is current;
- “Last known value” or Unavailable for stale evaluation context.

Update status chips, filters, summaries, and tests consistently if a label is
changed. The underlying API enum `suitable` need not change.

Likely touchpoint: `web/src/features/tanks/SpeciesCarePanel.tsx` and
`TankDetailPage.test.tsx`.

## Work item E — threshold boundary semantics

Current comparisons are intentionally strict/open. For bounds:

```text
critical low 6.0, warning low 6.5,
warning high 7.8, critical high 8.5
```

the engine produces:

```text
5.9 Critical; 6.0 Normal; 6.1 Warning; 6.5 Normal;
7.8 Normal; 7.9 Warning; 8.5 Normal; 8.6 Critical
```

Add helper text to the global-threshold page:

> Values must pass a configured boundary to trigger Warning or Critical. Exact
> boundary values remain within the Normal range.

Where practical, field context may say “Critical below”, “Warning below”,
“Warning above”, and “Critical above”. If the shorter existing labels remain,
the helper text is mandatory and must be programmatically associated or placed
prominently enough to be read before saving.

Do not change `decision_engine.py`, threshold ordering validation, stored
revisions, analytics, or historical results in this polish item.

Likely touchpoints:

- `web/src/features/thresholds/ThresholdsPage.tsx`
- `web/src/features/thresholds/ThresholdsPage.test.tsx`
- Phase 02 threshold documentation only if UI wording is recorded there

## Cross-surface review checklist

Search authenticated web surfaces for the following before completion:

- `Current readings`, `Latest reading`, and bare sensor labels shown offline;
- `Resolve`, `Resolving`, `Resolved by operator`, and notices using resolved for
  manual handling;
- broad `Suitable` claims without water context;
- help text that implies Species Care drives alerts;
- threshold labels that imply inclusive `>=`/`<=` behavior.

Do not mechanically replace historical data labels where “resolved” accurately
describes a database state. The goal is semantic clarity, not a blind string
replacement.

## Required validation

- Unit/component tests for current, stale, missing, and offline reading copy.
- A formatting test for short and long reporting ages, including null.
- Alert page and tank workspace tests for Mark handled wording and explanation.
- Species Care tests for water-only scope and differing operational/care states.
- Threshold page test for exact-boundary helper text.
- Typecheck, full web tests, and production build.
- Focused backend contract tests only if reporting age is added to tank
  operations.

## Acceptance criteria

- No offline value is presented as an unqualified current measurement.
- Reporting age uses server-receipt semantics where provided.
- Manual handling no longer claims physical recovery.
- Users can understand why operational Normal and Species Care Attention may
  coexist.
- Species Care does not imply pairwise compatibility or stocking safety.
- Administrators are told that exact threshold boundary values remain Normal.
- No evaluation algorithm, alert lifecycle, or historical record changes.

## Luna Extra High goal prompt

```text
You are working in the current AquaLogic repository. Implement the monitoring
and Species Care UI clarity goal in:
docs/deep-spec/final-hardening/03-ui-terminology-and-clarity.md

Read AGENTS.md, docs/INDEX.md, docs/DEVELOPMENT_STATUS.md, the final-hardening
hub, Phase 02 monitoring/alert specs, Phase 03 Species Care specs, and the web
area guide. Inspect the fleet, tank detail, alerts, Species Care, thresholds,
shared formatting/API models, tests, backend response schemas, and git status.

Before editing, produce a file-level plan with five checkpoints:
1. stale/offline values presented as last-known context using server-receipt age;
2. manual Resolve changed to Mark handled without changing backend lifecycle;
3. operational status explained separately from Species Care;
4. Species Care described as water-only, not fish compatibility;
5. strict/open threshold boundaries explained without algorithm changes.

Prefer a shared reporting-age formatter. Add the smallest authenticated backend
response field only if accurate tank-detail age cannot be derived from existing
server-receipt data. Do not use observation timestamps as freshness evidence.
Keep the 90-second freshness rule, strict threshold comparisons, alert
deduplication/resolution behavior, and advisory Species Care evaluator unchanged.
Fish compatibility remains notes-only and undecided.

Implement all five checkpoints consistently across visible copy, accessible
labels, status chips/filters where applicable, notices, and tests. Run focused
component/contract tests, then web typecheck, full tests, and build; run backend
tests if the API changes. Update API/phase docs when behavior or terminology
changes. Report changed files, validation, and acceptance-criteria coverage.
```

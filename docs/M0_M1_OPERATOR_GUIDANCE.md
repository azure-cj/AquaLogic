# M0/M1 operator alert detail implementation

Status: Implemented locally; validation and remaining limitations below
Date: 2026-10-02 (Asia/Manila)

## Baseline and preserved work

Implementation began on `fix/pump-controls-ux-copy`, commit
`ced73a6f30c9c38160ed1ab3a6c6e5c7ff3e3ba4`. The workspace container was
excluded; all work uses the nested AquaLogic repository.

Existing modified files were preserved: AGENTS.md; backend analytics service,
dashboard-management and sensor/public tests; DECISIONS, DEVELOPMENT_STATUS,
INDEX, Phase 04 Analytics and Phase 05 UV/lighting documentation; mobile
alerts_screen.dart; web Analytics source/tests and ActuatorControlPanel
source/tests. Existing untracked hero/login/tank image assets,
mvp-screenshots-2026-09-03 and mobile android/.kotlin were retained. Mobile
alerts_screen.dart received only contextual navigation additions over its
existing refresh work. No reset, checkout replacement, deployment, migration,
firmware or bridge change was performed.

The completed half-hour Analytics version was located in local history at
`a035e44c1f87765712506c90c7f651d191cdc4ec` (`main`, `origin/main`, and
`fix/pump-controls-production-copy`). Its source includes fixed half-hour
buckets, interval/tooltips and manual Refresh with successful update time.
The current branch predates it and retains variable resolutions without that
Refresh control. Existing uncommitted Analytics changes already separate
observation-time trends from receipt-time reporting. They were not rewritten
or replaced. Reconcile the branch/version explicitly before enabling the new
drawer's Analytics link. The current URL uses `tanks` and `metric`, not
`tank_id` and `parameter`; a verified target would be
`/admin/analytics?tanks=2&metric=temperature`.

The user-reported 219 backend/121 web checks belong to prior work. Our initial
checkout checks passed 217 backend, 118 web, and 198 Flutter tests. Backend
reported the existing Firebase Message.token deprecation warning. Counts differ
because this is an older branch; prior counts are not claimed as this run's
validation.

## Implemented contract and semantics

Staff/admin `GET /alerts/{alert_id}/context` derives context without persistence.
Existing list and resolve responses remain compatible. It returns the existing
AlertRead lifecycle, tank identity/lifecycle, evaluation time, nullable linked
and latest readings, nullable historical/current thresholds, and deterministic
guidance. Numeric reading context includes units, observation time, receipt
time, reading ID and reporting freshness. Latest selection uses receipt time
descending and reading ID descending, matching tank operations.

Historical effective bounds use the linked reading's receipt time and the shared
threshold revision resolver, including tank overrides and reset-to-global
history. These bounds are reconstructed, not an immutable detection snapshot.
Active alerts update their linked reading, severity and message on subsequent
abnormal readings. Clients label it **Reading linked to this alert** and label
the separate most recently received record **Latest received reading**. Recent
receipt does not prove an observation is current. Missing/unclear direction
uses unavailable generic guidance. Disabled current thresholds say disabled.

The catalogue covers temperature high/low, pH high/low, turbidity high and TDS
high/low using confirm/inspect/review/check language. It includes no diagnosis,
biological claim, dose, automated correction or assumed equipment telemetry.
Exact evaluator boundary behavior remains unchanged. Guidance is advisory.
Mark handled remains operator acknowledgement, not recovery verification;
system resolution can follow `reading_normal` or `threshold_disabled`. Existing
legacy/system/operator lifecycle remains readable, including retired tank
history; the existing backend active-tank guard still rejects retired handling.

Web AlertDetailDrawer loads one context when opened, supports retry and
`/admin/alerts?alert_id=123`, preserves filters on open/close, and opens from tank
active/history entries and fleet links identifying one alert. It provides tank,
history and role-aware equipment destinations. Administrator equipment uses
the existing actuator route; staff uses the tank Control panel and its existing
access explanation. No staff actuator access was added. Handling refreshes
context, alert history, tank operations and fleet caches; failed mutations do
not produce optimistic success.

Mobile uses a separate context DTO/domain model and repository method. Summary
remains visible during loading; context failure offers retry without invented
client guidance. Context updates lifecycle authoritatively and is reloaded
after successful handling. Existing Home/list reconciliation remains in use.
Tank and supported read-only equipment callbacks are shared by Home, tank
issues, Alerts and notification detail navigation. Retired handling and
equipment links are disabled. Mock context is explicitly demo/unavailable
context, not fabricated live measurements. Existing push auth restoration,
deduplication and authoritative record lookup remain unchanged.

Push creation copy now ends with “Open AquaLogic for details and suggested
checks.” Event keys, recipients, payload fields and creation-only triggers are
unchanged; repeated abnormal readings, handling and resolution enqueue no new
guidance events.

## Validation and limits

- Focused backend context/catalogue and existing monitoring/push checks passed.
- Web full suite passed 123 tests; typecheck and production build passed.
- Final backend suite passed 234 tests (existing Firebase deprecation warning);
  Flutter full suite passed 203 tests and analysis reported no issues.
- `git diff --check` passed. Temporary browser fixtures and the local preview
  process were removed after visual verification.
- Mobile responsive fixture checks cover 320-pixel width, loading/retry,
  authoritative handling, retired history and contextual navigation. Captures
  under evidence/operator-guidance use synthetic test data, not a device run.
- Browser fixture visual verification uses the shared drawer and synthetic API
  responses; it does not validate production authentication or deployment.
- Physical Android push-tap validation of this version remains pending. No
  device install or production mutation was performed.
- Analytics navigation remains disabled pending branch reconciliation. No
  Analytics implementation was changed by M0/M1.

## Completion demo

1. Open a high-temperature alert using View details or `alert_id` in the URL.
2. Show the linked reading, warning/critical bounds and both timestamps.
3. Show the latest received reading separately; explain receipt freshness versus
   observation time and the historical-bound reconstruction caveat.
4. Read the conservative measurement, optional heater, lighting and circulation
   checks. Open the tank, supported equipment destination and retained history.
5. Mark handled. Show operator acknowledgement and explain that this does not
   confirm water recovery. Refresh the detail and list/Home state.

## Follow-up checkpoint (2026-10-02)

The Analytics-disabled statements above record the M0/M1 completion checkpoint.
Approved M2/M3 subsequently reconciled the focused a035e44 half-hour Analytics
work and enabled tanks/metric navigation, preserving the baseline and M1.
See [M2/M3 implementation](M2_M3_IMPLEMENTATION.md) and
[isolated review](M2_M3_REVIEW_RUNBOOK.md) for current status.

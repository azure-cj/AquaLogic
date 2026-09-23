# Deferred Scope and Preserved Design

Classification: **Scope boundary and redesign guardrail**  
Status: Authoritative for the final hardening pass  
Last reviewed: 2026-09-23

## Purpose

Record what survived the stress review and what must remain outside the final
hardening pass. Deferred items are not TODOs.

## Preserved design — monitoring state

Current design is sound:

```text
fresh accepted reading -> Normal | Warning | Critical
no fresh accepted reading within 90 seconds -> Offline
```

Freshness uses server `received_at`. Old readings remain useful context but are
not current Normal. Missing supported values are unavailable. Species Care
cannot produce a confident suitable result from stale data.

Preserve one operational Offline state; do not add a separate Stale state in
this pass.

## Preserved design — alert incidents

Current active-alert behavior is sound:

- at most one active alert per tank and parameter;
- repeated abnormal readings update that incident;
- Warning can escalate to Critical and Critical can downgrade to Warning;
- a fresh Normal reading system-resolves the matching alert;
- operator-handled alerts remain distinct historical incidents;
- a later abnormal reading after operator closure creates a new alert.

Do not add acknowledgement, reopen, or recurring-alert aggregation without a
validated workflow.

## Preserved terminology boundary — alert versus notification

An **alert** is a persistent operational record of an abnormal condition. A
**notification** is a delivery mechanism used to inform someone.

AquaLogic currently has in-app alert surfaces, not push/email/SMS notification
delivery. Do not claim otherwise.

## Preserved design — global thresholds and Species Care

Global thresholds are administrator-configured defaults. A tank may have a
complete administrator-configured override per parameter, and assigned species
preferences never generate or alter those operational thresholds. Effective
thresholds drive operational status and alerts; Species Care remains advisory
care guidance and does not generate alerts.

Keep the engines separate. Exact operational threshold boundaries remain Normal
under the current strict/open algorithm. Species preferred-range endpoints
remain inside the preferred range; these are intentionally different contracts.

## Preserved design — device/tank ownership

- Device credentials identify a registered server-side device.
- The server-side device row determines the tank.
- The bridge cannot choose a tank in its reading payload.
- Historical readings keep original ownership.
- Physical moves use deactivation and new provisioning.

Do not add device reassignment or trust a client-supplied tank identifier.

## Preserved design — physical command fundamentals

Preserve:

- unique command identifiers;
- fixed device/tank binding;
- atomic claim before physical execution;
- queue expiry before claim;
- no blind automatic hardware retry;
- validated allowlisted payloads/actions;
- finalized command protection and idempotent matching reports;
- administrator authorization and persistent audit/history;
- guarded manual pump-maintenance scope.

Only the unresolved physical-outcome gap is approved for lifecycle hardening.

## Intentionally deferred — not implementation tasks

- Full/general fish compatibility engine.
- Breeding management.
- Spawning tracking.
- Fry management.
- Breeding pairs or groups.
- Breeding schedules.
- Pregnancy or reproduction tracking.
- Push notifications.
- Email alerts.
- SMS alerts.
- Automatic chemical dosing from sensor readings.
- Species-driven actuator automation.
- Automatic pump treatment logic.
- Large generalized pump schedule system.
- Per-tank AI recommendations.
- AI fish-care decision engine.
- General device reassignment system.
- Automatic physical-location detection.
- Enterprise monitoring infrastructure.
- Enterprise observability stack.
- Unnecessary business-intelligence functionality.
- Any hardware feature not justified by JRed's workflow, equipment, maintenance
  ability, and budget.

The following remains undecided and therefore deferred:

- curated fish-to-fish compatibility guidance.

Retired-tank history and persistent unattended monitoring incidents were
owner-approved as bounded work on 2026-08-21 and are implemented by packets 08
and 09. Their scope remains locked; that approval does not authorize adjacent
asset-management, external-notification, or enterprise-monitoring features.

## Review rule for future plans

If an implementation plan includes a deferred item, it must cite a new explicit
owner instruction or dated decision. “The review mentioned it” is not
sufficient authority.

# Pump Maintenance

Status: Implemented guarded maintenance workflow; automatic dosing deferred  
Last reviewed: 2026-08-21

## Purpose

Define the controlled manual checks for the two syringe pumps without turning
the current bridge into a chemical-treatment system.

## Current implemented behavior

Pump A and Pump B are available only from the administrator actuator workspace
and only as maintenance checks. Supported actions are:

- `dispense` / test
- `stop`
- `retract`

The bridge must have a fresh fixed-device heartbeat before a pump command is
queued. Pump testing is disabled by default through
`pump_manual_test_enabled` and must be enabled only for an intentional test
setup.

The UI requires confirmation before dispense/test and retract. Stop remains a
visible safety control. The maintenance warning instructs the tester to use
empty syringes or water only, keep both pumps clear of chemicals, and remain
ready to stop the equipment.

## Configured-volume dispense

The received firmware owns the configured dose volume and exposes no volume
setting endpoint. A dispense command therefore has an empty payload. The
bridge:

1. Reads both pump statuses and refuses to start while either pump is active.
2. Calls the selected firmware dispense route exactly once.
3. Polls the selected pump until the configured volume move reports complete.
4. Reports success only when completion is observed.
5. Uses a bounded completion timeout and may issue one intentional safety-stop
   request if the dispense does not complete safely.

The reported `volume_ml` is firmware state and is informational to AquaLogic;
the browser cannot edit it.

## Failure and retry behavior

- Pump commands default to a 20-second queue expiry and cannot exceed 30
  seconds before bridge claim.
- Pump commands are rejected with `409` while the bridge is offline.
- A timeout or ambiguous physical response is reported as failed.
- The bridge never retries a dispense, stop, or retract request automatically.
- The one safety stop after an unsafe or incomplete dispense is not a retry of
  the dispense action.
- A new dispense or retract command requires a fresh operator decision and
  confirmation; Stop remains available as the direct safety action.

## Permissions and audit

- Administrators only.
- No staff, public, mobile, or customer pump controls.
- Queue, claim, completion, failure, expiry, and state reports remain in the
  command and audit history.
- No device key, credential, or private hardware URL is exposed in the UI.

## Approved hardening and clarification

- Hardware validation must confirm stop behavior, safe physical setup, and
  configured-volume completion on the actual equipment.
- Production deployment requires a tested emergency procedure independent of
  the dashboard.

## Deferred scope

- Automatic chemical dosing.
- pH auto-dose.
- Sensor-driven dosing.
- Pump schedules.
- Editable firmware dose configuration.
- Mobile, public, staff, or customer pump controls.

## Acceptance criteria

- Pump controls are visibly maintenance-only and administrator-only.
- Offline pump commands are rejected rather than queued.
- Dispense uses the firmware-configured volume and no client duration payload.
- An incomplete dispense may receive one safety stop but is never retried.
- The UI and docs warn against chemical use during testing.

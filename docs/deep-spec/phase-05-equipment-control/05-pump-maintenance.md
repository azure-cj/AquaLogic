# Pump Maintenance

Status: Implemented guarded maintenance workflow with uncertainty interlock; automatic dosing deferred
Last reviewed: 2026-08-22

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

Before tank deletion or a physical move, finish or physically verify any pump
work, stop the equipment, and follow the [hardware decommissioning and
move/reprovisioning workflow](../../WORKFLOWS.md#moving-equipment-to-another-tank).
An executing or uncleared `outcome_unknown` command requires administrator
physical verification before the same-device/same-pump dispense lock can be
cleared; Stop remains available during the lock. Deactivating the registered
device or deleting its database rows does not prove that a pump stopped or that
firmware-resident configuration was erased.

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

Before another dispense, AquaLogic reconciles stale commands and blocks the
same registered device plus same pump while an earlier dispense is `executing`
or uncleared `outcome_unknown`. Pump A does not block Pump B or another device.
Stop remains available during the lock. Retract remains an explicit,
confirmation-gated maintenance action but does not clear the lock or prove that
the earlier dispense did not occur.

## Failure and retry behavior

- Pump commands default to a 20-second queue expiry and cannot exceed 30
  seconds before bridge claim.
- Pump commands are rejected with `409` while the bridge is offline.
- A bridge-reported timeout/failure follows the bridge failure path. If AquaLogic
  then loses the terminal report past the 180-second confirmation window, the
  command becomes `outcome_unknown`: physical execution may have occurred and
  the command is never automatically retried.
- The bridge never retries a dispense, stop, or retract request automatically.
- The one safety stop after an unsafe or incomplete dispense is not a retry of
  the dispense action.
- A new dispense or retract command requires a fresh operator decision and
  confirmation; Stop remains available as the direct safety action.
- An administrator can record physical verification with a bounded note. This
  clears the software dispense lock while preserving the original
  `outcome_unknown` history.

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
- A same-device/same-pump dispense is blocked while an earlier dispense is
  executing or uncleared unknown, and physical verification is attributable.
- The UI and docs warn against chemical use during testing.

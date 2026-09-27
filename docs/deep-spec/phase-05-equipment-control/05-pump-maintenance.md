# Pump Maintenance

Status: Implemented guarded water-only maintenance and device-resident chemical schedules
Last reviewed: 2026-09-27

## Purpose

Define the controlled manual checks for the two syringe pumps without turning
the current bridge into a chemical-treatment system.

## Current implemented behavior

Pump A and Pump B are available from the administrator actuator workspace for
water-only maintenance tests and fixed-volume schedule configuration. Supported
bridge actions are:

- `dispense` (manual chemical dose through the local device dashboard or an
  explicitly authorized bridge command)
- `test_dispense` (water-only maintenance; no chemical cooldown)
- `stop`
- `retract`
- `schedule` (three device-resident chemical-dose slots)
- `refill_confirm` (volume estimate only; no motor movement)

The bridge must have a fresh fixed-device heartbeat before a pump command is
queued. Pump testing is disabled by default through
`pump_manual_test_enabled` and must be enabled only for an intentional test
setup.

The UI requires confirmation before a water-only test, retract, refill
confirmation, and enabling any chemical schedule slot. Stop remains a visible
safety control. Tests use empty syringes or water only, keep both pumps clear
of chemicals, and remain ready to stop the equipment. Optional
threshold-driven pH auto-dose remains device-local and disabled by default.

Before tank deletion or a physical move, finish or physically verify any pump
work, stop the equipment, and follow the [hardware decommissioning and
move/reprovisioning workflow](../../WORKFLOWS.md#moving-equipment-to-another-tank).
An executing or uncleared `outcome_unknown` command requires administrator
physical verification before the same-device/same-pump dispense lock can be
cleared; Stop remains available during the lock. Deactivating the registered
device or deleting its database rows does not prove that a pump stopped or that
firmware-resident configuration was erased.

## Configured-volume dispense

The firmware owns the configured dose volume and exposes no volume setting
endpoint. Maintenance-test and schedule commands use empty payloads for the
physical action; a schedule carries three validated `enabled`/`HH:MM` slots.
The bridge:

1. Reads both pump statuses and refuses to start while either pump is active.
2. Calls the selected firmware dispense route exactly once.
3. Polls the selected pump until the configured volume move reports complete.
4. Reports success only when completion is observed.
5. Uses a bounded completion timeout and may issue one intentional safety-stop
   request if the dispense does not complete safely; the command remains
   `outcome_unknown` because the physical result cannot be inferred from the
   timeout or stop response.

The status flow reports the configured dose and tracked volume state. Both
syringes have a tracked 5 mL capacity; at the default 1 mL dose that allows
five doses. A fresh or depleted syringe blocks dosing until an administrator
physically checks/refills it and confirms the refill through either UI. That
confirmation only updates the estimated volume and does not move the motor or
reset cooldown. Retract remains a separate motor action and does not claim a
refill.

Manual chemical doses, Pump A/B schedules, and optional pH auto-dose share one
persisted two-hour minimum cooldown. A water-only maintenance test tracks the
selected syringe's volume but does not start that chemical cooldown. Before a
local chemical dispense, the dashboard asks the operator to check the syringe
and reports the configured dose and next eligible time. The administrator
schedule confirmation identifies the fixed mL dose, local times, cooldown,
and the fact that blocked occurrences are skipped.

Schedules and pump safety state are stored in ESP32 NVS. Chemical dosing and
schedule execution remain paused after a cold boot until router-synchronized
Asia/Manila NTP time is valid. If a scheduled occurrence is blocked by
cooldown, volume, pump activity, or persistence failure, it is skipped, shown
in device status/dashboard and surfaced as an administrator toast; it is not
retried or caught up.

Before another dispense, AquaLogic reconciles stale commands and blocks the
same registered device plus same pump while an earlier dispense is `executing`
or uncleared `outcome_unknown`. Pump A does not block Pump B or another device.
Stop remains available during the lock. Retract remains an explicit,
confirmation-gated maintenance action but does not clear the lock or prove that
the earlier dispense did not occur.

## Failure and retry behavior

- Pump motion commands default to a 20-second queue expiry and cannot exceed
  30 seconds before bridge claim. Schedule and motor-free refill configuration
  commands default to 120 seconds and cannot exceed 300 seconds, allowing the
  bridge's sensor-first polling cycle to claim configuration work without
  relaxing the expiry for pump motion.
- Pump commands are rejected with `409` while the bridge is offline.
- A confirmed pre-dispatch or explicit non-ambiguous rejection is `failed`. A
  post-dispatch timeout, lost/malformed response, completion timeout, or
  state-poll failure is `outcome_unknown`: physical execution may have occurred
  and the command is never automatically retried. The server's 180-second
  confirmation deadline remains a second, unattended safety net.
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

- Backend-generated automatic dose commands and scheduler workers.
- Editable firmware dose configuration.
- Mobile, public, staff, or customer pump controls.

## Acceptance criteria

- Web maintenance controls are visibly water-only; chemical schedules require
  administrator confirmation, and all browser pump controls are admin-only.
- Offline pump commands are rejected rather than queued.
- Dispense uses the firmware-configured volume and no client duration payload.
- An incomplete dispense may receive one safety stop but is never retried.
- A same-device/same-pump dispense is blocked while an earlier dispense is
  executing or uncleared unknown, and physical verification is attributable.
- The UI and docs warn against chemical use during testing.

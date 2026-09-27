# Feeding Schedules

Status: Implemented device-resident schedules using synchronized local time
Last reviewed: 2026-09-28

## Purpose

Define the current schedule contract without implying that AquaLogic operates a
backend scheduler.

## Current implemented behavior

The feeder and each syringe pump accept exactly three schedule slots. Each slot contains:

- `enabled`
- `time` in `HH:MM` format

The schedule is sent as one validated actuator command to the registered
device. The bridge forwards the command to the ESP32, and the ESP32 owns local
execution after accepting it.

The UV and normal LED daily schedules contain one enabled flag and on/off
`HH:MM` values. Pump slots configure fixed-volume chemical doses independent
of current pH. All pump slots start disabled.

When equipment is physically moved, schedules do not follow a database device
mapping. The operator must disable intended source schedules before the move,
provision the destination identity, verify the new device and equipment
identity, and recreate only the intended schedules through the [canonical
move/reprovisioning workflow](../../WORKFLOWS.md#moving-equipment-to-another-tank).
Database deletion or device deactivation does not erase firmware-resident
schedule state.

## Execution and history

- AquaLogic validates and queues schedule configuration.
- The bridge claims and forwards the command once.
- The ESP32 stores schedule settings and per-day occurrence keys in NVS and
  evaluates them locally using router-synchronized NTP time configured for
  Asia/Manila (`PHT-8`).
- AquaLogic receives schedule state during bridge refreshes and shows the
  latest known configuration.
- AquaLogic does not create a separate command for each autonomous event.
- Command history records the schedule configuration request, not each future
  automatic feeding or lighting event.
- A successful command means the device accepted the configuration request; it
  does not prove every future event will execute.

## Failure behavior

- A schedule update may remain queued while the bridge is unavailable.
- Pump schedule configuration defaults to a 120-second queue expiry and may be
  configured up to 300 seconds. This allows for the bridge's 15-second polling
  interval plus sensor/backlog work before command retrieval. Pump motion
  commands keep their 20-second default and 30-second maximum.
- If it reaches its expiry before the bridge claims it, it is marked expired and
  is never delivered.
- The application does not silently claim that a failed update replaced the
  device's existing schedule.
- A confirmed pre-dispatch rejection is reported as failed. A timeout, lost or
  malformed response after dispatch, or other ambiguous request is reported as
  `outcome_unknown` and is not automatically retried.
- An operator may issue a new schedule command only after checking the device
  and the currently reported schedule.

## Time model

The wire contract remains `HH:MM`; the ESP32 applies it as Asia/Manila time.
The firmware synchronizes from NTP through the router. After a cold boot,
schedule execution and chemical dosing remain paused until NTP time is valid;
no RTC hardware is present. NVS retains schedule settings and each local-date
occurrence key so rebooting during a scheduled minute does not repeat a pump
dose or feeder event. Slots are disabled by default.

Pump schedules use the configured fixed mL dose regardless of current pH. Both
pumps, manual chemical dispensing, and optional threshold-driven pH auto-dose
share a persistent two-hour minimum cooldown. If a scheduled pump is busy,
cooling down, lacks confirmed volume, or cannot persist its safety state, that
occurrence is skipped, exposed through pump status, and not caught up later.
See [Pump Maintenance](05-pump-maintenance.md) for volume and refill behavior.

## Permissions and audit

- Schedule configuration is administrator-only.
- Staff and public callers cannot read or change actuator schedules through
  the browser APIs.
- Schedule queue, claim, result, failure, expiry, and state-report activity is
  retained in the existing actuator history/audit trail.

## Approved hardening and clarification

- Asia/Manila timezone and NTP clock synchronization are implemented on the
  device. Schedule versioning and delivery confirmation semantics remain
  possible future refinements.
- Any scheduler worker or system actor must be separately designed before
  AquaLogic begins generating autonomous commands.

## Deferred scope

- Backend scheduler workers.
- Additional recurrence types beyond the current daily schedules.
- Router-dependent NTP time during cold boot without Wi-Fi; no hardware RTC.
- Per-event schedule history as a separate user-facing timeline.
- Fleet-wide schedule orchestration.

## Acceptance criteria

- The docs distinguish schedule configuration delivery from autonomous device
  execution.
- No future automatic event is represented as a separate AquaLogic command.
- Expired schedule updates are not described as applied.
- Current `HH:MM` and three-slot limits are documented.
- Device-clock limitations and future scheduler work are explicit.

# Feeding Schedules

Status: Implemented device-resident configuration; scheduling expansion deferred  
Last reviewed: 2026-08-21

## Purpose

Define the current schedule contract without implying that AquaLogic operates a
backend scheduler.

## Current implemented behavior

The feeder accepts exactly three schedule slots. Each slot contains:

- `enabled`
- `time` in `HH:MM` format

The schedule is sent as one validated actuator command to the registered
device. The bridge forwards the command to the ESP32, and the ESP32 owns local
execution after accepting it.

The same device-resident model applies to the current UV and normal LED daily
schedules, which contain one enabled flag and on/off `HH:MM` values.

## Execution and history

- AquaLogic validates and queues schedule configuration.
- The bridge claims and forwards the command once.
- The ESP32 stores and executes the schedule locally.
- AquaLogic receives schedule state during bridge refreshes and shows the
  latest known configuration.
- AquaLogic does not create a separate command for each autonomous event.
- Command history records the schedule configuration request, not each future
  automatic feeding or lighting event.
- A successful command means the device accepted the configuration request; it
  does not prove every future event will execute.

## Failure behavior

- A schedule update may remain queued while the bridge is unavailable.
- If it reaches its expiry before the bridge claims it, it is marked expired and
  is never delivered.
- The application does not silently claim that a failed update replaced the
  device's existing schedule.
- A bridge timeout or ambiguous request is reported as failed and is not
  automatically retried.
- An operator may issue a new schedule command only after checking the device
  and the currently reported schedule.

## Time model

The current wire contract sends local `HH:MM` values and contains no timezone,
daylight-saving, or device-clock synchronization fields. The effective clock
for autonomous execution is therefore the ESP32's current local clock. This
limitation must be visible to operators and is not converted into a server
timezone claim.

## Permissions and audit

- Schedule configuration is administrator-only.
- Staff and public callers cannot read or change actuator schedules through
  the browser APIs.
- Schedule queue, claim, result, failure, expiry, and state-report activity is
  retained in the existing actuator history/audit trail.

## Approved hardening and clarification

- A future schedule design may define timezone, daylight-saving, clock-sync,
  schedule versioning, and delivery confirmation semantics.
- Any scheduler worker or system actor must be separately designed before
  AquaLogic begins generating autonomous commands.

## Deferred scope

- Backend scheduler workers.
- Schedule recurrence beyond the current device contract.
- Timezone and daylight-saving management.
- Sensor-driven schedules and automatic chemical dosing.
- Schedule history as a separate user-facing timeline.
- Fleet-wide schedule orchestration.

## Acceptance criteria

- The docs distinguish schedule configuration delivery from autonomous device
  execution.
- No future automatic event is represented as a separate AquaLogic command.
- Expired schedule updates are not described as applied.
- Current `HH:MM` and three-slot limits are documented.
- Device-clock limitations and future scheduler work are explicit.

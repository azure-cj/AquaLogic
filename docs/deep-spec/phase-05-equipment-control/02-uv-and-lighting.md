# UV and Lighting Controls

Status: Implemented v1 controls; production hardware hardening deferred  
Last reviewed: 2026-08-21

## Purpose

Define the administrator-only controls for the UV light and normal aquarium
LED without adding a new lighting automation platform.

## Current implemented behavior

The focused actuator workspace supports both `uv` and `led` with these
actions:

- `on`
- `off`
- `timer`
- `schedule`

Timer duration is validated from 1 millisecond through 86,400,000
milliseconds. The web form presents this as 1–86,400 seconds.

Daily schedules contain `enabled`, `on_time`, and `off_time` values in `HH:MM`
format. The bridge translates the validated values to the existing ESP32 light
routes.

Reported light state includes:

- current on/off state
- remaining timer duration
- cumulative on-time value when reported by the device
- schedule enabled state
- configured on and off times

The browser shows the latest validated state and labels missing state as
unknown. State becomes stale when the bridge stops reporting.

## Schedule execution

Lighting schedules are device-resident:

1. AquaLogic validates the schedule payload.
2. The backend creates one expiring command.
3. The bridge claims the command before making one ESP32 request.
4. The ESP32 stores and executes the schedule locally.
5. AquaLogic displays the latest schedule state reported during bridge refresh.

A successful schedule command confirms that the ESP32 accepted the
configuration request. It does not confirm every future scheduled execution.
The backend does not run a lighting scheduler and does not create a separate
command for each scheduled on/off event.

## Permissions and audit

- Only administrators can read light state or queue light commands.
- Staff and public callers do not receive lighting controls.
- The device key is used only by the bridge.
- Queueing, claiming, completion, failure, expiry, and state reports remain in
  the command/audit history.
- The browser never contacts the ESP32 directly.

## Failure and safety behavior

- Invalid action/payload combinations are rejected before delivery.
- Commands that remain queued past their expiry are not returned to the bridge.
- A bridge timeout or ambiguous physical response is reported as failed without
  blindly repeating the hardware request.
- A stale state report does not prove that the light is physically off.

## Approved hardening and clarification

- Production hardware validation must establish safe behavior after bridge loss
  and confirm the device's schedule clock assumptions.
- Timezone, daylight-saving, and device-clock management are not represented
  by the current `HH:MM` contract and require a separately approved design.

## Deferred scope

- Sensor-driven lighting.
- Predictive or recommendation-based lighting.
- Multi-zone scenes and fleet orchestration.
- Public, staff, or mobile lighting controls.
- Direct ESP32 access from the browser or internet.

## Acceptance criteria

- Administrators can turn each supported light on or off, start a bounded
  timer, and save a daily schedule.
- Invalid durations and time values are rejected.
- Device-resident schedule behavior is distinguished from backend scheduling.
- Command expiry, no-blind-retry, and stale-state warnings are visible in the
  documented lifecycle.

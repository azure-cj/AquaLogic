# Fish Feeder Control

Status: Implemented v1 controls; advanced feeding automation deferred  
Last reviewed: 2026-08-21

## Purpose

Define the administrator-only manual and configuration controls for the
registered fish feeder.

## Current implemented behavior

The actuator workspace supports:

- `Feed now`, with a confirmation step.
- Feeder configuration using an opening angle from 0–180 degrees.
- Feeder duration from 500–60,000 milliseconds.
- Up to three daily schedule slots.
- Per-slot enabled state and `HH:MM` time.

Reported feeder state includes feeding status, feed count, last-fed value,
opening angle, duration, and the three schedule slots.

All payloads are validated by the backend and validated again by the bridge
before an ESP32 request is made. The device's fixed tank mapping remains the
authority for delivery.

## Manual feeding workflow

1. An administrator selects `Feed now`.
2. The UI asks for confirmation of the tank and feeder.
3. AquaLogic queues a validated feeder command with a server expiry.
4. The bridge claims it and makes one exact feeder request.
5. The bridge reports success or failure and refreshes state when possible.

An uncertain or timed-out request is not automatically sent again. An operator
must inspect the equipment before issuing a new command.

## Schedule behavior

Feeder schedules are device-resident configuration:

1. AquaLogic validates the three-slot payload.
2. The backend queues one schedule command.
3. The bridge forwards it once to the ESP32.
4. The ESP32 stores and runs the schedule locally.

AquaLogic does not execute feeding schedules or create a command for every
autonomous feed. A successful schedule command confirms configuration delivery,
not every future feed. If a new schedule command expires before delivery, the
application does not claim that the device received the replacement.

## Permissions and audit

- Only administrators can read feeder state, configure the feeder, or feed
  manually.
- Staff, public callers, and mobile clients cannot use feeder controls.
- Queue, claim, success, failure, expiry, and state-report events remain
  auditable.
- Device keys, credentials, and raw bridge configuration are never shown in
  the browser.

## Approved hardening and clarification

- Device-clock, timezone, and daylight-saving behavior for `HH:MM` schedules
  require a separate design and hardware validation.
- Production use requires confirmation of feeder behavior after bridge loss and
  a validated local emergency procedure.

## Deferred scope

- Stocking-based feed calculations.
- Automatic portion recommendations.
- Sensor-driven feeding.
- Customer or staff feeding access.
- Multiple-feeder orchestration.
- Cloud scheduler workers and external notification delivery.

## Acceptance criteria

- Manual feeding requires confirmation and creates an auditable command.
- Feeder angle, duration, and three-slot schedule bounds are enforced.
- Device-resident schedule execution is distinguished from backend scheduling.
- Offline or stale bridges can cause queued commands to expire.
- Hardware requests are never blindly retried.

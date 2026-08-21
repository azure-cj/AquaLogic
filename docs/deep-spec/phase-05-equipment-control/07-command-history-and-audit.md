# Command History and Audit

Status: Implemented bounded administrator history and audit trail  
Last reviewed: 2026-08-21

## Purpose

Define the persistent record of administrator physical-control activity and
bridge-reported actuator state.

## Current implemented behavior

The administrator actuator workspace reads newest-first history for the fixed
device/tank mapping. History supports:

- default page size of 10
- maximum page size of 50
- previous/next pagination metadata
- actuator filtering for UV, LED, feeder, Pump A, or Pump B
- lifecycle-status filtering for queued, executing, succeeded, failed, or
  expired
- command/action name
- actor
- requested, expiry, claim, and completion timestamps
- validated payload
- result or error
- expandable command details

Each response also includes fixed-device summary counts for total, queued,
executing, succeeded, failed, and expired commands. Summary counts remain
available while row filters are active.

Actuator state history is append-only. Each bridge state report records the
device, fixed tank, actuator, reported state, report time, and optional command
reference. The latest validated state is stored separately for fast status
display.

## Audit events

The current lifecycle records audit activity for:

- command queueing
- command claim/executing transition
- successful completion
- reported failure
- queued-command expiry
- actuator state reporting

The history and audit trail preserve physical-control context after a command
has completed. Payloads and results contain validated operational data only;
device keys, key hashes, refresh tokens, passwords, and private credentials are
not included.

## Permissions and privacy

- Only administrators can read browser actuator history.
- Staff receives `403` and the web client does not fetch the history route for
  staff accounts.
- Device-key bridge routes can append state and lifecycle records only for the
  authenticated device's fixed tank.
- Pagination prevents the browser from loading an unbounded command response.

## Approved hardening and clarification

- Production operations may later define retention, export, and archival
  requirements after hardware and deployment ownership are established.
- If a backend scheduler is introduced later, its system-actor identity and
  audit semantics must be designed before schedule-generated commands exist.

## Deferred scope

- A formal retention period.
- Archive/export workflows.
- A separate schedule-event history.
- System attribution for future scheduler-generated commands.
- Public or staff audit access.

## Acceptance criteria

- Administrators can inspect bounded, filterable, newest-first command history.
- Lifecycle summary counts remain meaningful with filters active.
- State history is append-only and tied to the fixed device/tank.
- Physical-control events remain auditable after completion.
- Sensitive credentials and device secrets never appear in history responses.

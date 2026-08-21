# Command Lifecycle

Status: Implemented lifecycle and safety boundary  
Last reviewed: 2026-08-21

## Purpose

Define the lifecycle of a physical actuator command from administrator request
through bridge delivery and result reporting.

## Current implemented behavior

The backend stores these states:

| Backend state | UI label | Meaning |
| --- | --- | --- |
| `queued` | Waiting | Validated and waiting for the fixed bridge device |
| `executing` | Executing | Claimed by the device before the physical call |
| `succeeded` | Succeeded | The bridge received a valid firmware response and reported completion |
| `failed` | Failed | Validation, network, timeout, or firmware-response failure was reported |
| `expired` | Expired | The command was still queued when its expiry passed and was not sent |

Normal UV, LED, and feeder commands default to a 120-second expiry and may be
configured up to 300 seconds. Pump commands default to 20 seconds and may not
exceed 30 seconds before bridge claim.

## Lifecycle rules

1. The administrator request is validated and assigned a server-generated
   command ID.
2. The command is bound to one fixed registered device and tank.
3. The bridge retrieves only unexpired commands for its authenticated device.
4. The bridge claims the command before any physical ESP32 request.
5. The bridge makes one allowlisted physical request.
6. The bridge reports success or failure and attempts a state refresh.
7. Finalized commands cannot be claimed, requeued, or physically executed
   again.

Pending queue expiry is enforced by the backend and bridge. An executing
command is finalized by its result report rather than being silently converted
to a queued retry.

## Success and acknowledgement semantics

Success means the bridge received a valid response from the intended firmware
endpoint and reported it to AquaLogic. State refresh is best effort and is not
required to repeat the physical command. For device-resident schedules,
success confirms configuration acceptance, not every future scheduled event.

For pump dispense, success additionally requires observation that the
firmware-configured volume move completed. A bounded timeout may trigger one
intentional safety stop before the command is reported failed.

## Retry and duplicate behavior

- There is no automatic hardware retry.
- An ambiguous timeout is treated as potentially executed and is not blindly
  repeated.
- Duplicate bridge claims return a conflict and cannot execute the command
  twice.
- Duplicate final reports are idempotent and cannot requeue a finalized command.
- There is no retry endpoint or retry button. An operator may issue a new
  command only after checking the physical equipment.
- Pump safety stop is a deliberate one-shot safety action, not a retry.

## Permissions and isolation

- Browser command creation is administrator-only.
- Bridge command lifecycle transitions are authorized by the registered device
  key.
- A device can claim or report only commands mapped to its own fixed tank.
- Staff and public users cannot create, read, or finalize actuator commands.

## Approved hardening and clarification

- Production hardware tests must validate endpoint acknowledgement, state
  refresh timing, stop behavior, and safe handling of ambiguous responses.
- Future cancellation or operator retry workflows require a separate command
  safety design; they are not implied by the current lifecycle.

## Deferred scope

- Automatic retries.
- In-place command editing or cancellation.
- Backend scheduler-generated commands.
- Chemical dosing workflows.
- Cross-device failover and fleet orchestration.

## Acceptance criteria

- Every command has a visible, auditable lifecycle state.
- Expired commands are never delivered to hardware.
- A command is claimed before physical execution.
- Final reports are idempotent.
- Hardware requests are never blindly retried.
- Success is not overstated as proof of future schedule execution or current
  physical state.

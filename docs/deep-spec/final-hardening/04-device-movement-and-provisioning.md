# Device Movement and Reprovisioning

Classification: **Implemented operational workflow record; general reassignment deferred**
Status: Implemented canonical operational workflow  
Last reviewed: 2026-08-22

## Objective

Make the safe current hardware-move workflow explicit while preserving
server-side reading ownership and historical integrity.

## Verified current model

- A registered device credential resolves to one fixed `tank_id` on the server.
- Bridge reading payloads cannot select an arbitrary tank; extra `tank_id`
  fields are rejected by the reading schema.
- A tank may currently have multiple active registered devices.
- Normal device management supports provisioning, activation/deactivation, and
  key rotation, but not reassignment or deletion.
- Historical readings store their original tank and nullable source device.
- Actuator commands and state are also tied to the registered device and tank.

This fixed mapping is a safety and integrity feature. Editing a device row to
point at another tank would blur the meaning of history and could misidentify
attached equipment.

## Canonical operator runbook

The durable operator procedure lives in
[`docs/WORKFLOWS.md#moving-equipment-to-another-tank`](../../WORKFLOWS.md#moving-equipment-to-another-tank).
This packet defines the safety and data-integrity contract behind that
procedure; it is not an API or database reassignment design.

## Required move workflow

Treat a physical move as a new provisioning event:

```text
1. Identify the source tank, registered device, and attached actuators.
2. Finish or physically verify pending equipment work. Resolve any
   executing/uncleared pump uncertainty through the administrator physical
   verification flow before treating the move as complete; the original
   unknown command remains in history.
3. Disable device-resident schedules and stop equipment where appropriate.
   Confirm the physical result; a database action cannot erase firmware state.
4. Deactivate the existing device registration in **Devices**. This immediately
   rejects the old key for sensor ingestion and actuator delivery while
   preserving the old identity and its historical records.
5. Stop or disconnect the old bridge configuration, then confirm the old key
   no longer ingests readings or claims commands. A `401` from the deactivated
   identity is expected; it is not evidence that the equipment itself stopped.
6. Physically move and reconnect the hardware. Confirm the destination tank,
   sensor wiring, actuator labels, pump A/B plumbing, and local power state.
7. Provision a new device registration for the destination tank. Use a new
   device identifier and the administrator-only provisioning response; never
   edit the old row's `tank_id`.
8. Configure the bridge with the newly issued one-time device key. The bridge
   does not receive a tank selector; the server-side registration supplies the
   destination mapping. Keep the key out of logs, screenshots, tickets, and
   repository files.
9. Confirm the bridge reports **Online** for the new identity and that a fresh
   reading has the new `device_id`, the destination `tank_id`, server receipt
   time, supported units, and plausible values.
10. Confirm that no new reading is arriving on the source tank under the old
    identity. If another active device exists on either tank, identify it
    explicitly before treating a reading as evidence of this move.
11. Verify UV/LED/feeder and Pump A/B physical identity against the destination
    device and the latest reported state before controls resume. Last-known
    state is diagnostic context, not proof of physical state.
12. Recreate only the intended device-resident schedules for the destination.
    After each schedule command, read back the device state; a successful
    configuration request does not prove every future event will execute.
```

The old registration remains inactive as the historical identity. Never paste
or log either old or new raw keys in documentation or screenshots.

## Failure and rollback guidance

- If a pending command is `executing` or `outcome_unknown`, do not start a
  replacement dispense. Keep **Stop** available, inspect the physical pump,
  and have an administrator record verification before the same-device,
  same-pump dispense lock is cleared. Clearance does not rewrite the command
  to succeeded or failed.
- If provisioning or bridge configuration fails, keep the old identity
  deactivated while the hardware is at the destination. If the hardware is
  physically returned to the source tank, an administrator may reactivate the
  old registration only after verifying the complete physical identity; if its
  key was rotated, configure the replacement key instead. A newly created
  destination registration may be deactivated, but its fixed mapping and
  history are not edited or merged.
- If new readings appear on the source tank, stop the bridge and inspect which
  credential/configuration is running before changing any registration.
- If readings appear on both tanks, check for a second active bridge/device and
  its fixed mapping; do not guess which data is authoritative.
- If equipment identity or schedule state is uncertain, keep normal controls
  disabled and verify locally before sending commands. An ambiguous actuator
  request is never blindly retried.
- Do not rewrite or migrate historical readings to the destination tank.
- Do not claim that deactivation, deletion, or any other database action erased
  firmware schedules, firmware configuration, or physical actuator state.

## Documentation placement

During implementation/documentation reconciliation:

- keep the operator procedure in the canonical
  [`docs/WORKFLOWS.md`](../../WORKFLOWS.md) section;
- link it from the Phase 01 monitoring-device and bridge specs;
- link it from the Phase 05 equipment-connection, schedule, pump-maintenance,
  and command-lifecycle specs;
- link it from tank deletion/decommissioning guidance;
- ensure device-management wording does not suggest that deactivation or key
  rotation changes a device's fixed tank mapping or clears physical schedules.

No backend or web feature change is required solely to satisfy this packet
unless the existing UI actively suggests reassignment or automatic cleanup.

## Acceptance criteria

- An administrator can follow one documented move procedure without editing the
  database or trusting a bridge-supplied tank ID.
- Historical records remain with the source tank and old device identity.
- The destination uses a newly provisioned identity and one-time key.
- Fresh readings and actuator identity are verified before normal operations.
- Device-resident schedules are explicitly rechecked rather than assumed moved
  or erased.

## Non-goals

- General device reassignment API/UI.
- Automatic physical-location detection.
- Moving historical readings between tanks.
- Automatic cloning of schedules or actuator state.
- Device deletion or credential recovery.

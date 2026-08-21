# Equipment Connection

Status: Implemented local bridge boundary; production hardware hardening deferred  
Last reviewed: 2026-08-21

## Purpose

Define how AquaLogic communicates with registered tank equipment and how the
application presents connection freshness before physical controls are used.

## Current implemented behavior

- Each registered device has one fixed server-side tank mapping.
- The browser never receives a device key and never connects directly to the
  ESP32.
- Browser actuator routes require an administrator JWT.
- Bridge ingestion and actuator delivery routes require the registered device's
  `X-Device-Key`.
- A device is online when it is active and its last server-observed activity is
  within the current 90-second freshness window.
- Active devices with no recent activity are offline. Inactive devices are
  disabled. Actuator status may also be `unknown` when no device activity has
  been observed yet.
- The actuator workspace displays connection freshness, last update time,
  offline/stale warnings, and the latest validated state reported by the
  bridge.

## Command and connection behavior

1. An administrator queues a validated command for a tank and its selected
   registered device.
2. The bridge authenticates with the device key and retrieves only commands
   for that device and fixed tank.
3. The bridge claims a command before making a physical ESP32 request.
4. The bridge reports the result and refreshes local actuator state on a
   best-effort basis.

Light and feeder commands may remain queued while a bridge is unavailable and
can expire before delivery. Pump maintenance commands require an online bridge
and are rejected rather than silently queued while it is offline.

## Safety rule

Last-known actuator state is diagnostic context, not proof of the current
physical state. A stale or offline bridge does not prove that an actuator is
off. The UI must continue to warn operators and must not present stale state as
fresh confirmation.

## Permissions and isolation

- Administrators may read actuator status, queue commands, and read history.
- Staff receives `403` for actuator command, state, and history routes.
- Device-key routes cannot be authorized with a browser JWT.
- A device cannot select another tank through an ingestion or actuator request.
- Multiple active devices per tank remain supported; operations that require one
  device must select it explicitly when necessary.

## Approved hardening and clarification

- Production deployment must add hardware-validated fail-safe behavior and a
  tested response to bridge loss before physical control is considered
  production-ready.
- Future monitoring may distinguish bridge availability from confirmed
  actuator state, but this phase does not claim physical-off guarantees from a
  stale report.

## Deferred scope

- Public or staff actuator controls.
- Mobile actuator controls.
- Direct public ESP32 exposure.
- Fleet-wide device orchestration or failover.
- Automatic chemical dosing and sensor-driven safety automation.

## Acceptance criteria

- The browser never stores or receives a device key.
- Staff and unauthenticated callers cannot use actuator routes.
- Device requests remain bound to their registered tank.
- Offline/stale status is visible before physical control use.
- Pump maintenance cannot be queued while the fixed bridge is offline.
- Documentation does not describe last-known state as guaranteed physical state.

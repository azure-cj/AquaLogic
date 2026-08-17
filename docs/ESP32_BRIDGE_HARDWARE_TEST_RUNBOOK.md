# ESP32 bridge hardware-test runbook

Status: Temporary local-first sensor and actuator test procedure
Last reviewed: 2026-08-15

## Safety and scope

- The tester laptop and ESP32 must stay on the same private local Wi-Fi.
- The ESP32 is never placed behind a tunnel or exposed to the internet.
- One temporary HTTPS tunnel may expose the owner dashboard/API only.
- The bridge is the only component that calls the ESP32 actuator endpoints.
- v1 controls UV, normal LED, fish feeder, and Pump A/B manual tests only.
  Pump schedules, pH auto-dose, and sensor-driven dosing are not available in
  AquaLogic.
- Pump tests are dry-run mechanical checks only: use empty syringes or water,
  never chemicals. Confirm the physical setup before every dispense or retract
  command and keep the visible Stop control ready.
- The tester-only `pump_manual_test_enabled` setting defaults to `false` and
  must be `true` only during a controlled empty/water motor test.
- Hardware calls are one-shot. A timeout may mean the actuator already ran, so
  the bridge reports the failure and does not retry that physical command.
- Keep the one-time device key and local `bridge-config.json` private and
  untracked. Never put Wi-Fi credentials or device secrets in repository files,
  console output, screenshots, or tickets.

## Owner computer

From the nested repository root, use separate PowerShell terminals:

```powershell
cd backend
.\.venv\Scripts\activate
alembic upgrade head
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

```powershell
cd web
npm run dev -- --host 127.0.0.1 --port 5173
```

Create one temporary HTTPS dashboard tunnel with the approved tunnel provider.
For example:

```powershell
ngrok http 5173
```

Share only the dashboard URL with the tester. The bridge backend URL is that
same URL with `/api` appended. Do not create a tunnel to the ESP32 or a second
ESP32 tunnel.

Provision one device with an administrator session, using the API docs or:

```powershell
curl.exe -X POST http://127.0.0.1:8000/devices `
  -H "Authorization: Bearer <ADMIN_JWT>" `
  -H "Content-Type: application/json" `
  -d '{"device_id":"esp32-test-01","tank_id":<TANK_ID>}'
```

Record the returned device key securely for the tester. It is not a staff
password, browser token, or tank selector.

## Hardware tester computer

Connect to the same private Wi-Fi as the ESP32. Obtain its local IP from the
LCD or serial monitor and verify only the sensor endpoint locally:

```powershell
Invoke-WebRequest http://<ESP32_LOCAL_IP>/data
```

Prepare the local, untracked bridge configuration:

```powershell
cd <AquaLogic repository>
Copy-Item bridge\bridge-config.example.json bridge\bridge-config.json
notepad bridge\bridge-config.json
```

Fill placeholders only with the local test values:

```json
{
  "esp32_data_url": "http://<ESP32_LOCAL_IP>/data",
  "aqualogic_backend_url": "https://<DASHBOARD_TUNNEL>/api",
  "device_key": "<ONE_TIME_PROVISIONED_DEVICE_KEY>",
  "poll_interval_seconds": 15,
  "timeout_seconds": 5,
  "actuator_enabled": true,
  "pump_manual_test_enabled": false
}
```

Run one diagnostic cycle first:

```powershell
python bridge\esp32_bridge.py --config bridge\bridge-config.json --once
```

Then run the continuous bridge:

```powershell
python bridge\esp32_bridge.py --config bridge\bridge-config.json
```

The bridge validates and forwards sensor readings, polls pending commands,
calls only the allowlisted local routes, and reports state/results. It does not
print the device key or Wi-Fi configuration.

For a controlled pump test only, confirm the physical setup is empty or
water-only, then change `pump_manual_test_enabled` to `true`. Select a 100,
250, 500, 1,000, 1,500, or 2,000 ms dispense cutoff in the admin dashboard.
The bridge calls the exact dispense endpoint once and then the matching stop
endpoint after the cutoff; it never retries either physical call. Return the
flag to `false` after testing.

## Dashboard verification

1. Sign in to the shared dashboard as an administrator and open the tank mapped
   during provisioning.
2. Confirm the Actuator controls panel shows the registered device and bridge
   online/freshness state.
3. Verify last-known UV, normal LED, and feeder state appears. A stale/offline
   bridge is not evidence that the physical actuator is off.
4. Test UV and LED on, off, timer, schedule enable/disable, and schedule time
   changes one at a time.
5. Use **Feed now** only after confirming the tank and feeder, and complete the
   confirmation dialog. Test feeder configuration within 0–180° and
   500–60,000 ms, then test its three schedule slots.
6. For Pump A/B, confirm the manual-test warning and physical setup. Use
   **Dispense / test** only with an empty syringe or water, confirm the dialog,
   keep **Stop** ready, and use **Retract** only after confirming the mechanism
   is clear. Do not enable pump schedules or pH auto-dose.
7. Verify each command moves through the audit history with the admin actor,
   request time, result/error, and final status.
8. Sign in as staff in a separate session. Controls must not be usable, and
   direct actuator command/status/history API calls must receive 403.
9. Disconnect the ESP32 or stop the bridge. The dashboard should become stale /
   offline after the freshness window and must not fabricate state.

## Failure checks

- Invalid ESP32 JSON or an invalid actuator response creates a failed command
  report and does not trigger a second hardware request.
- An unreachable ESP32 does not create a fabricated sensor reading. A command
  that may have timed out is not automatically retried.
- An unreachable backend prevents new command delivery/reporting but does not
  expose the ESP32.
- Expired queued commands are not returned by the device pending API and are
  never executed later.
- The bridge never calls `/feeder/test`, pump schedule/config/jog, or pH
  auto-dose routes. Pump dispense/stop/retract are the only pump actions and
  require the tester flag.

## After testing

- Stop the bridge, tunnel, backend, and dashboard processes.
- Keep `bridge\bridge-config.json` private and uncommitted.
- Do not edit the firmware, pins, wiring, or Wi-Fi configuration as part of
  this test.
- Record calibration and hardware observations separately from source control.

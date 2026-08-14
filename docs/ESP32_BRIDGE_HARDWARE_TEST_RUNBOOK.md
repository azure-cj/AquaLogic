# ESP32 bridge hardware-test runbook

Status: Temporary local-first test procedure
Last reviewed: 2026-08-14

## Owner computer

From the repository root, use separate PowerShell terminals:

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

Create one temporary public HTTPS dashboard tunnel with the approved tunnel
provider. For example, with ngrok installed:

```powershell
ngrok http 5173
```

Share the HTTPS dashboard tunnel with testers. The Vite development proxy
forwards its `/api` path to the local backend, so use
`https://<dashboard-tunnel>/api` as the bridge backend URL. Do not create a
tunnel to the ESP32 or a second ngrok tunnel.
Provision a device with an administrator session as described in
[`ESP32_BRIDGE_INTEGRATION_PLAN.md`](ESP32_BRIDGE_INTEGRATION_PLAN.md), record
the one-time returned device key securely, and map it to the intended tank.

## Hardware tester computer

Connect to the ESP32's Wi-Fi network. Obtain its private LAN address from the
LCD or serial monitor and verify only `http://<ESP32-IP>/data` opens locally.

```powershell
cd <AquaLogic repository>
Copy-Item bridge\bridge-config.example.json bridge\bridge-config.json
# Edit bridge-config.json: local ESP32 /data URL, owner's HTTPS backend tunnel,
# and the provisioned device key. Do not commit this file.
python bridge\esp32_bridge.py --config bridge\bridge-config.json --once
python bridge\esp32_bridge.py --config bridge\bridge-config.json
```

The console reports forward successes and retry/backoff errors. Invalid JSON,
invalid values, or an unreachable endpoint produce no fabricated sensor record.

## Verification

Open the owner's dashboard tunnel, sign in as staff, and open the mapped tank.
Verify temperature, pH, turbidity, TDS, observation time, and a current status.
Dissolved oxygen and ammonia must show **Not installed** / unavailable. Stop
the bridge (or disconnect the ESP32) and wait more than 90 seconds; the tank
must show an offline/stale state, not fresh readings. This is test
infrastructure only: close tunnels when the session is complete.

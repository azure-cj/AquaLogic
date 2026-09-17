# AquaLogic — Offline Buffering & Backlog Sync: Handoff Summary

## What this feature does
The ESP32 controller previously lost any sensor readings taken while it had no WiFi
connection to the router — the device only ever held the single "latest reading" in memory,
so an outage silently erased that window of history. This feature adds local buffering on
the device plus a matching sync path in the bridge script, so no data is lost during a
WiFi outage, and a manual testing tool to trigger/verify that outage behavior on demand.

## Architecture (unchanged, confirmed, important to respect)
```
ESP32 (local WiFi only, never touches the internet)
    │  polled by
Bridge script (esp32_bridge.py, runs on a machine on the same LAN)
    │  forwards over HTTPS with X-Device-Key auth
Backend (POST /device-ingestion/readings, one reading per request)
```
The ESP32 never calls the internet directly. All new work respects this — the device only
ever serves data locally; the bridge is solely responsible for reaching the backend.

## What was built, in order

### 1. ESP32: non-blocking WiFi + local offline buffer
- Replaced the old **blocking** `while (WiFi.status() != WL_CONNECTED) delay(500);` in
  `setup()` with a non-blocking connect/retry state machine (`serviceWiFi`), so the device
  boots and keeps running (feeder, dosing, LCD, sensors) with no WiFi at all.
- While `wifiConnected == false`, sensor readings are buffered locally to flash (LittleFS,
  append-only NDJSON), batched to limit flash wear, capped in size/count with oldest-first
  drop on overflow (tracked via a `droppedRecords` counter).
- New read-only endpoints on the ESP32's existing local HTTP server:
  - `GET /data/backlog?limit=N` — oldest N un-acked buffered records (each has a `seq`)
  - `GET /data/backlog/count` — `{pending, dropped, oldest_seq, newest_seq}`
  - `POST /data/backlog/ack?upto=<seq>` — deletes records with `seq <= upto`
- The existing `GET /data` endpoint (live latest reading) is **unchanged** — untouched
  contract, other consumers unaffected.

### 2. ESP32: manual offline-mode testing panel
- Added `GET /wifi/disconnect` and `GET /wifi/reconnect` for **deliberately** testing the
  buffering behavior without needing to unplug the router.
- Disconnect fully drops STA WiFi and starts a fallback SoftAP (`AquaLogic-Debug`,
  reachable at `192.168.4.1`) so the dashboard stays reachable for testing — otherwise the
  device would go completely unreachable with no station-mode fallback.
- A 2-minute safety auto-reconnect prevents the device from getting permanently stranded in
  test mode if nobody presses "Reconnect."
- Dashboard got two small new panels: a read-only "OFFLINE BUFFER" status box (pending /
  dropped / oldest / newest seq), and a "TESTING — WIFI OFFLINE SIMULATION" panel with the
  disconnect/reconnect buttons and live connection-state readout.

### 3. Bridge: backlog draining
- On every poll cycle, after the normal live `/data` fetch/forward, the bridge now also
  checks `GET /data/backlog/count`. If non-zero, it drains the backlog in batches (default
  50 records/batch, capped at 500 records/cycle) by forwarding each record through the
  **same** `POST /device-ingestion/readings` call, headers, and field mapping already used
  for live readings — no new backend endpoint was added.
- Acks only happen after a confirmed backend success, and only up to the last *confirmed*
  record in a partially-failed batch — so a mid-batch failure doesn't cause duplicate
  inserts on retry, and doesn't lose already-confirmed records either.
- Backlog-drain failures are logged distinctly (`[BACKLOG] ...`) and do **not** trigger the
  bridge's normal exponential backoff — that backoff is reserved for live-poll failures, so
  a backlog hiccup doesn't throttle live data unnecessarily.
- 5 new tests cover: zero-pending skip, single/multi-batch drain, ack-only-on-confirmation,
  partial-batch failure (confirmed prefix acked, rest retried next cycle), per-cycle cap.

### 4. Bridge: timestamp estimation for backlogged records
- The ESP32 has no RTC/NTP, so backlogged records have no real wall-clock time attached —
  only fixed the far worse bug where every backlogged record was being stamped with the
  **drain time** instead of anything resembling its actual sample time (could be off by the
  entire outage duration, corrupting ordering and any time-based analysis).
- Replaced with **even-spread estimation**: backlogged records are linearly interpolated
  between "last known-good live reading time" and "now," in `seq` order. This is an
  approximation, not a real timestamp — correct relative ordering, not correct absolute time.
- Records are tagged with `time_estimated=true` / `estimation_method="even_spread"`
  internally, but **these markers are currently stripped before hitting the backend**,
  because the backend's `SensorReadingCreate` schema uses `extra="forbid"` and would reject
  the payload otherwise. So today, an estimated timestamp and a real one are
  **indistinguishable once stored** — this was a deliberate scope decision, not an oversight
  (see below).
- 6 new tests cover: even-spread monotonicity, reboot-mid-outage edge case, flag stripped at
  the wire, no-anchor fallback, anchor-update timing.

## Known, deliberate gaps (not bugs — scoped decisions)

1. **No NTP/RTC on the ESP32.** This is the root cause of the timestamp-estimation need.
   Adding `configTime()`/NTP sync to the sketch would give backlogged records real epoch
   timestamps and make most of the even-spread estimation unnecessary (it would only be
   needed as a fallback for the rare "device rebooted mid-outage" case). **Recommended next
   step if timestamp accuracy matters** — higher leverage than the backend migration below.

2. **`time_estimated` flag not persisted to the backend.** Currently safe to skip —
   functionally everything works without it, readings are stored and displayed normally.
   What you lose by skipping it: no way to later distinguish "measured" from "estimated"
   timestamps in stored data. Only matters if someone will do rigorous historical analysis,
   alerting, or cross-device time comparison on data that includes buffered/estimated
   readings. If needed later: add `time_estimated: bool` (+ optional `estimation_method`
   string) to `DeviceReadingCreate` / `SensorReading` model, Alembic migration, wire through
   `ingest_device_reading` (`backend/app/routes/devices.py:490`), expose in
   `SensorReadingRead`, then stop stripping the flag in the bridge before forwarding.

3. **Single bridge instance per device, always sequential.** Confirmed with the project
   owner: an owner-bridge and a tester-bridge are never run concurrently against the same
   physical ESP32. Backlog ack logic is intentionally simple (`seq` cutoff, no batch tokens)
   because of this — if concurrent bridges against one device ever becomes a real scenario,
   the ack mechanism would need revisiting to avoid a race where one bridge acks records the
   other hasn't yet confirmed to the backend.

4. **mDNS across WiFi mode switches.** Switching STA → AP → STA (for the manual offline
   test panel) may not cleanly restore `aqualogic.local` mDNS resolution without an explicit
   `MDNS.end()` / `MDNS.begin()` cycle — flagged during implementation, verify this was
   actually handled (check the diff / test notes) before relying on the hostname after using
   the disconnect/reconnect test panel.

## Where to look in the code
- `AquaLogic_Offline.ino` (or whatever it was saved as) — WiFi state machine, LittleFS
  buffer, backlog endpoints, manual offline-mode + AP fallback, dashboard panels.
- `bridge/esp32_bridge.py` — `drain_backlog()`, `_estimate_observed_at`,
  `_backlog_estimate_window`, wired into `run_once()`.
- `bridge/tests/test_esp32_bridge.py` — all new backlog + timestamp tests.
- `docs/DECISIONS.md` — recorded rationale for the design choices above.
- Hardware test runbook — has the "Offline backlog draining" section with manual test steps.

## Before trusting this on real hardware
1. **The ESP32 sketch has not been compiled** — all validation so far was static/structural
   (regex checks, diff hygiene), not an actual build, because no Arduino toolchain was
   available in the dev environment. Compile it (Arduino IDE or `arduino-cli`) before
   flashing.
2. Run the full manual test sequence end to end once on real hardware: force-disconnect via
   the test panel, confirm buffering, reconnect, confirm the bridge drains the backlog and
   the backend receives it, confirm timestamps look reasonable (not all identical).
3. Confirm the mDNS behavior noted in gap #4 above.

# Tank Console primary firmware contract

Reviewed 2026-10-06 against commit 248c698, repository path `esp32`.

Phase 2B (2026-10-07) re-inspected this unchanged source. Its enabled command
subset and acknowledgement limits are documented in
[TANK_CONSOLE_PHASE_2B.md](TANK_CONSOLE_PHASE_2B.md). Phase 2A references below
describe the earlier read-only checkpoint, not the current Console capability.

## Identity and limits

The newest full firmware source is the **extensionless** root file `esp32`, not a tracked `.ino` path. `esp32-config` was last changed at a946ee6 (2026-09-27), while `esp32` was updated at 248c698 (2026-10-04). `Aqualogic.ino` is the older limited sketch. A collaborator must confirm the actual Arduino sketch/binary flashed on the device; Git does not prove deployment.

`WebServer(80)` is serviced synchronously in loop(). Most server.on registrations omit a method: the bundled Arduino WebServer default is HTTP_ANY, not GET-only. Phase 2A uses only six explicit GET paths and never touches command, Wi-Fi, demo, schedule or backlog routes.

The no-method overload uses HTTP_ANY in [Espressif WebServer](https://github.com/espressif/arduino-esp32/blob/master/libraries/WebServer/src/WebServer.cpp). The collaborator's installed Arduino library version is not recorded here.

## Exact read schemas (JSON types, not sample values)

- `/data`: `{temp_c: number, temp_status: string, ph_value: number, ph_status: string, turbidity_ntu: number, turbidity_status: string, tds_ppm: number, tds_status: string, overall_status: string}`.
- `/led/status` and `/uv/status`: `{led_on: boolean, remaining_ms: integer, total_on_ms: integer, schedule_enabled: boolean, sched_on: string, sched_off: string}`. **UV also uses led_on.** Schedule strings have HH:MM format.
- `/feeder/status`: `{feeding: boolean, feed_count: integer, last_fed: string, open_angle: integer, duration_ms: integer, schedule: [{hour: integer, minute: integer, enabled: boolean}]}`. Exactly three schedule slots.
- `/syringeA/status` and `/syringeB/status`: `{active: boolean, dose_count: integer, last_dispensed: string, volume_ml: number, remaining_ml: number, capacity_ml: number, volume_known: boolean, refill_required: boolean, clock_synced: boolean, last_chemical_dose_at: string, next_eligible_at: string, next_dose_at: string, schedule_event: string, schedule: [{hour: integer, minute: integer, enabled: boolean}]}`. Exactly three schedule slots. Time strings are firmware-formatted, including unavailable/empty time representations; they are not guaranteed ISO timestamps.
- `/wifi/status`: `{connected: boolean, sta_connected: boolean, sta_reconnecting: boolean, fallback_ap_active: boolean, manual_offline: boolean, manual_offline_remaining_ms: integer, mode: string, ip: string, sta_ip: string, ap_ip: string, ap_ssid: string}`. Not fetched by Phase 2A. STA disconnected does **not** mean the device cannot be reached through its AP.
- `/data/backlog`: array of `/data` objects plus `seq: integer` (no sample timestamp). `/data/backlog/count`: `{pending: integer, dropped: integer, oldest_seq: integer, newest_seq: integer}`. Only the gateway should acknowledge backlog.

The response construction appendix below records every registered route's exact static response literals and dynamic JSON construction, including error branches. Dynamic string variables are firmware text, not promises of successful physical movement. See linked handlers for branching conditions. HTML at `/` is not JSON.

## Wi-Fi, discovery and timing

STA uses configured credentials in source (not reproduced here). Automatic fallback AP starts after 12 seconds without STA; it uses SSID `AquaLogic-Debug-ESP32` and the standard softAP address 192.168.4.1. AP+STA allows STA retries. AP is stopped after 15 seconds of stable STA recovery. Manual offline uses AP-only and has a 120-second timeout before STA recovery. These policies are firmware-owned; the Console does not invoke them.

mDNS starts on successful STA connection as `aqualogic`, advertising `_http._tcp` port 80: `aqualogic.local`. No explicit `WiFi.setHostname("esp32")` or `esp32.local` configuration was found. A single-label name `esp32` works only if the router/DNS happens to resolve it; do not assume it. Phase 2A accepts a configured name but adds no discovery/NSD. Android mDNS name resolution requires physical verification; use a private IPv4 address/DHCP reservation initially.

Sensor refresh is gated by millis() >= 2000 in loop(), but DallasTemperature conversion, ADC averaging, HTTP and storage work can delay the loop. `/data` has no boot/sample sequence, uptime, capture timestamp or validity flags, so receipt freshness cannot prove fresh physical sampling or detect a frozen firmware reading.

## Status and actuator semantics

Firmware overall_status is GOOD / MONITOR / CRITICAL; the app maps these existing labels only and invents no water thresholds. Individual status strings come directly from firmware. Temperature is a raw DallasTemperature result (including -127 disconnect sentinel); analog values may be clamped and do not expose disconnected-probe validity. pH uses `calculateDemoPH` (piecewise voltage calibration clamped to 5..10) regardless of the separate demo-mode flag. Turbidity is explicitly described in source as prototype, not laboratory-grade NTU calibration. Hardware calibration needs verification.

Status booleans describe firmware state/motion, not independent physical feedback. Feeder inactive means ready/not moving, not food availability. Pump inactive means idle/not moving, not dose permission. LED manual commands set a manual override; UV manual commands do not share exactly the same schedule override semantics. Schedules remain device-owned.

No HTTP authentication, command IDs or idempotency registry were found. `/feeder/feed` responds fed:true even if already feeding and skipped; `/syringe*/retract` similarly can report retracted:true when skipped. Dispensed:true means a pump move was accepted, not completed. Chemical doses have persisted shared two-hour cooldown, mutual exclusion, known-volume and remaining-volume checks, with NTP requirements. Test-dispense bypasses chemical cooldown/time checks and must be protected before dosing control is considered. Do not infer physical success from HTTP 200.

## All registered endpoints

| Path | Firmware method restriction | Handler |
| --- | --- | --- |
| `/` | ANY (GET supported) | [`handleRoot`](../esp32#L3763) |
| `/data` | ANY (GET supported) | [`handleData`](../esp32#L3771) |
| `/data/backlog` | GET | [`handleBacklog`](../esp32#L3667) |
| `/data/backlog/count` | GET | [`handleBacklogCount`](../esp32#L3692) |
| `/data/backlog/ack` | POST | [`handleBacklogAck`](../esp32#L3724) |
| `/wifi/disconnect` | ANY (GET supported) | [`handleWiFiDisconnect`](../esp32#L3627) |
| `/wifi/reconnect` | ANY (GET supported) | [`handleWiFiReconnect`](../esp32#L3633) |
| `/wifi/status` | ANY (GET supported) | [`handleWiFiStatus`](../esp32#L3638) |
| `/feeder/status` | ANY (GET supported) | [`handleFeederStatus`](../esp32#L3837) |
| `/feeder/feed` | ANY (GET supported) | [`handleFeedNow`](../esp32#L3909) |
| `/feeder/test` | ANY (GET supported) | [`handleFeederTest`](../esp32#L3921) |
| `/feeder/config` | ANY (GET supported) | [`handleFeederConfig`](../esp32#L3933) |
| `/feeder/schedule` | ANY (GET supported) | [`handleFeederSchedule`](../esp32#L3960) |
| `/syringeA/status` | ANY (GET supported) | [`handleSyrAStatus`](../esp32#L4021) |
| `/syringeA/dispense` | ANY (GET supported) | [`handleSyrADispense`](../esp32#L4121) |
| `/syringeA/test-dispense` | ANY (GET supported) | [`handleSyrATestDispense`](../esp32#L4134) |
| `/syringeA/refill-confirm` | ANY (GET supported) | [`handleSyrARefillConfirm`](../esp32#L4146) |
| `/syringeA/stop` | ANY (GET supported) | [`handleSyrAStop`](../esp32#L4164) |
| `/syringeA/retract` | ANY (GET supported) | [`handleSyrARetract`](../esp32#L4175) |
| `/syringeA/schedule` | ANY (GET supported) | [`handleSyrASchedule`](../esp32#L4190) |
| `/syringeB/status` | ANY (GET supported) | [`handleSyrBStatus`](../esp32#L4247) |
| `/syringeB/dispense` | ANY (GET supported) | [`handleSyrBDispense`](../esp32#L4348) |
| `/syringeB/test-dispense` | ANY (GET supported) | [`handleSyrBTestDispense`](../esp32#L4361) |
| `/syringeB/refill-confirm` | ANY (GET supported) | [`handleSyrBRefillConfirm`](../esp32#L4373) |
| `/syringeB/stop` | ANY (GET supported) | [`handleSyrBStop`](../esp32#L4391) |
| `/syringeB/retract` | ANY (GET supported) | [`handleSyrBRetract`](../esp32#L4402) |
| `/syringeB/schedule` | ANY (GET supported) | [`handleSyrBSchedule`](../esp32#L4417) |
| `/ph/auto/status` | ANY (GET supported) | [`handlePhAutoStatus`](../esp32#L4474) |
| `/ph/auto/config` | ANY (GET supported) | [`handlePhAutoConfig`](../esp32#L4530) |
| `/demo/status` | ANY (GET supported) | [`handleDemoStatus`](../esp32#L4585) |
| `/demo/ph` | ANY (GET supported) | [`handleDemoPh`](../esp32#L4613) |
| `/demo/mode` | ANY (GET supported) | [`handleDemoMode`](../esp32#L4636) |
| `/uv/status` | ANY (GET supported) | [`handleUvStatus`](../esp32#L4696) |
| `/uv/on` | ANY (GET supported) | [`handleUvOn`](../esp32#L4780) |
| `/uv/off` | ANY (GET supported) | [`handleUvOff`](../esp32#L4798) |
| `/uv/timer` | ANY (GET supported) | [`handleUvTimer`](../esp32#L4815) |
| `/uv/schedule` | ANY (GET supported) | [`handleUvSchedule`](../esp32#L4852) |
| `/led/status` | ANY (GET supported) | [`handleLedStatus`](../esp32#L5003) |
| `/led/on` | ANY (GET supported) | [`handleLedOn`](../esp32#L5087) |
| `/led/off` | ANY (GET supported) | [`handleLedOff`](../esp32#L5102) |
| `/led/timer` | ANY (GET supported) | [`handleLedTimer`](../esp32#L5116) |
| `/led/schedule` | ANY (GET supported) | [`handleLedSchedule`](../esp32#L5150) |

## Exact response construction appendix

Extracted from current source; String(...) serializes the indicated firmware variable. The source link contains branch conditions and input validation. No credentials are included.


### `/` — `handleRoot`

```cpp
server.send(
      200,
      "text/html",
      DASHBOARD_HTML
    );
```


### `/data` — `handleData`

```cpp
String json="{";
json +=
      "\"temp_c\":"+
      String(
        temperatureC,
        2
      )+",";
json +=
      "\"temp_status\":\""+
      tempStatus+
      "\",";
json +=
      "\"ph_value\":"+
      String(
        phValue,
        2
      )+",";
json +=
      "\"ph_status\":\""+
      phStatus+
      "\",";
json +=
      "\"turbidity_ntu\":"+
      String(
        turbidityNtu,
        1
      )+",";
json +=
      "\"turbidity_status\":\""+
      turbidityStatus+
      "\",";
json +=
      "\"tds_ppm\":"+
      String(
        tdsPpm,
        0
      )+",";
json +=
      "\"tds_status\":\""+
      tdsStatus+
      "\",";
json +=
      "\"overall_status\":\""+
      overallStatus+
      "\"";
json+="}";
server.send(
      200,
      "application/json",
      json
    );
```


### `/data/backlog` — `handleBacklog`

```cpp
String json = "[";
json += ",";
json += line;
json += ",";
json += ramBuffer[i];
json += "]";
server.send(200, "application/json", json);
```


### `/data/backlog/count` — `handleBacklogCount`

```cpp
String json = "{\"pending\":" + String(pending) +
      ",\"dropped\":" + String(droppedRecords) +
      ",\"oldest_seq\":" + String(oldest) +
      ",\"newest_seq\":" + String(newest) + "}";
server.send(200, "application/json", json);
```


### `/data/backlog/ack` — `handleBacklogAck`

```cpp
server.send(400, "application/json", "{\"error\":\"missing upto\"}");
server.send(400, "application/json", "{\"error\":\"invalid upto\"}");
server.send(400, "application/json", "{\"error\":\"upto exceeds queued sequence\"}");
server.send(200, "application/json", "{\"ack\":\"accepted\"}");
```


### `/wifi/disconnect` — `handleWiFiDisconnect`

```cpp
server.send(200, "application/json", "{\"disconnecting\":true,\"ap_ssid\":\"" DEBUG_AP_SSID "\"}");
```


### `/wifi/reconnect` — `handleWiFiReconnect`

```cpp
server.send(200, "application/json", "{\"reconnecting\":true}");
```


### `/wifi/status` — `handleWiFiStatus`

```cpp
String json = "{\"connected\":" + String(wifiConnected ? "true" : "false") +
      ",\"sta_connected\":" + String(staConnected ? "true" : "false") +
      ",\"sta_reconnecting\":" + String(!staConnected && !manualOfflineMode ? "true" : "false") +
      ",\"fallback_ap_active\":" + String(fallbackApActive ? "true" : "false") +
      ",\"manual_offline\":" + String(manualOfflineMode ? "true" : "false") +
      ",\"manual_offline_remaining_ms\":" + String(remaining) +
      ",\"mode\":\"" + wifiModeName() +
      "\",\"ip\":\"" + ip +
      "\",\"sta_ip\":\"" + staIp +
      "\",\"ap_ip\":\"" + apIp +
      "\",\"ap_ssid\":\"" + apSsid + "\"}";
server.send(200, "application/json", json);
```


### `/feeder/status` — `handleFeederStatus`

```cpp
String json="{";
json +=
      "\"feeding\":"+
      String(
        feederActive
          ?"true"
          :"false"
      )+",";
json +=
      "\"feed_count\":"+
      String(feedCount)+",";
json +=
      "\"last_fed\":\""+
      lastFedTime+
      "\",";
json +=
      "\"open_angle\":"+
      String(feederOpenAngle)+",";
json +=
      "\"duration_ms\":"+
      String(feederDurationMs)+",";
json +=
      "\"schedule\":[";
json +=
        "{\"hour\":"+
        String(
          feedSchedule[i].hour
        )+",";
json +=
        "\"minute\":"+
        String(
          feedSchedule[i].minute
        )+",";
json +=
        "\"enabled\":"+
        String(
          feedSchedule[i].enabled
            ?"true"
            :"false"
        )+
        "}";
json+=",";
json+="]}";
server.send(
      200,
      "application/json",
      json
    );
```


### `/feeder/feed` — `handleFeedNow`

```cpp
server.send(
      200,
      "application/json",
      "{\"fed\":true}"
    );
```


### `/feeder/test` — `handleFeederTest`

```cpp
server.send(
      200,
      "application/json",
      "{\"tested\":true}"
    );
```


### `/feeder/config` — `handleFeederConfig`

```cpp
server.send(400, "application/json", "{\"config\":\"invalid\"}");
server.send(503, "application/json", "{\"config\":\"not_saved\"}");
server.send(
      200,
      "application/json",
      "{\"config\":\"saved\"}"
    );
```


### `/feeder/schedule` — `handleFeederSchedule`

```cpp
server.send(400, "application/json", "{\"schedule\":\"invalid\"}");
server.send(503, "application/json", "{\"schedule\":\"not_saved\"}");
server.send(503, "application/json", "{\"schedule\":\"marker_reset_failed\"}");
server.send(
      200,
      "application/json",
      "{\"schedule\":\"saved\"}"
    );
```


### `/syringeA/status` — `handleSyrAStatus`

```cpp
String json="{";
json +=
      "\"active\":"+
      String(
        syringeAActive
          ?"true"
          :"false"
      )+",";
json +=
      "\"dose_count\":"+
      String(
        syringeADoseCount
      )+",";
json +=
      "\"last_dispensed\":\""+
      syringeALastDispensed+
      "\",";
json +=
      "\"volume_ml\":"+
      String(
        syringeADispenseML,
        2
      )+",";
json +=
      "\"remaining_ml\":"+
      String(
        syringeARemainingML,
        2
      )+",";
json +=
      "\"capacity_ml\":"+
      String(
        syringeACapacityML,
        2
      )+",";
json += "\"volume_known\":" + String(syringeAVolumeKnown ? "true" : "false") + ",";
json += "\"refill_required\":" + String(refillRequired ? "true" : "false") + ",";
json += "\"clock_synced\":" + String(deviceClockSynchronized() ? "true" : "false") + ",";
json += "\"last_chemical_dose_at\":\"" + lastChemical + "\",";
json += "\"next_eligible_at\":\"" + nextEligibleText + "\",";
json += "\"next_dose_at\":\"" + formatDeviceEpoch(nextDose) + "\",";
json += "\"schedule_event\":\"" + syringeALastScheduleEvent + "\",";
json += "\"schedule\":[";
json +=
        "{\"hour\":"+
        String(
          syringeASchedule[i].hour
        )+",";
json +=
        "\"minute\":"+
        String(
          syringeASchedule[i].minute
        )+",";
json +=
        "\"enabled\":"+
        String(
          syringeASchedule[i].enabled
            ?"true"
            :"false"
        )+
        "}";
json+=",";
json+="]}";
server.send(
      200,
      "application/json",
      json
    );
```


### `/syringeA/dispense` — `handleSyrADispense`

```cpp
server.send(200, "application/json", "{\"dispensed\":true}");
server.send(409, "application/json", "{\"dispensed\":false,\"reason\":\"" + reason +
        "\",\"next_eligible_at\":\"" + formatDeviceEpoch(nextChemicalEligibleEpoch()) + "\"}");
```


### `/syringeA/test-dispense` — `handleSyrATestDispense`

```cpp
server.send(200, "application/json", "{\"dispensed\":true}");
server.send(409, "application/json", "{\"dispensed\":false,\"reason\":\"" + reason + "\"}");
```


### `/syringeA/refill-confirm` — `handleSyrARefillConfirm`

```cpp
server.send(409, "application/json", "{\"refill_confirmed\":false,\"reason\":\"Pump busy or persistent state unavailable\"}");
server.send(503, "application/json", "{\"refill_confirmed\":false,\"reason\":\"Could not persist refill confirmation\"}");
server.send(200, "application/json", "{\"refill_confirmed\":true}");
```


### `/syringeA/stop` — `handleSyrAStop`

```cpp
server.send(
      200,
      "application/json",
      "{\"stopped\":true}"
    );
```


### `/syringeA/retract` — `handleSyrARetract`

```cpp
server.send(
      200,
      "application/json",
      "{\"retracted\":true}"
    );
```


### `/syringeA/schedule` — `handleSyrASchedule`

```cpp
server.send(400, "application/json", "{\"schedule\":\"invalid\"}");
server.send(503, "application/json", "{\"schedule\":\"not_saved\"}");
server.send(503, "application/json", "{\"schedule\":\"marker_reset_failed\"}");
server.send(200, "application/json", "{\"schedule\":\"saved\"}");
```


### `/syringeB/status` — `handleSyrBStatus`

```cpp
String json="{";
json +=
      "\"active\":"+
      String(
        syringeBActive
          ?"true"
          :"false"
      )+",";
json +=
      "\"dose_count\":"+
      String(
        syringeBDoseCount
      )+",";
json +=
      "\"last_dispensed\":\""+
      syringeBLastDispensed+
      "\",";
json +=
      "\"volume_ml\":"+
      String(
        syringeBDispenseML,
        2
      )+",";
json +=
      "\"remaining_ml\":"+
      String(
        syringeBRemainingML,
        2
      )+",";
json +=
      "\"capacity_ml\":"+
      String(
        syringeBCapacityML,
        2
      )+",";
json += "\"volume_known\":" + String(syringeBVolumeKnown ? "true" : "false") + ",";
json += "\"refill_required\":" + String(refillRequired ? "true" : "false") + ",";
json += "\"clock_synced\":" + String(deviceClockSynchronized() ? "true" : "false") + ",";
json += "\"last_chemical_dose_at\":\"" + lastChemical + "\",";
json += "\"next_eligible_at\":\"" + nextEligibleText + "\",";
json += "\"next_dose_at\":\"" + formatDeviceEpoch(nextDose) + "\",";
json += "\"schedule_event\":\"" + syringeBLastScheduleEvent + "\",";
json +=
      "\"schedule\":[";
json +=
        "{\"hour\":"+
        String(
          syringeBSchedule[i].hour
        )+",";
json +=
        "\"minute\":"+
        String(
          syringeBSchedule[i].minute
        )+",";
json +=
        "\"enabled\":"+
        String(
          syringeBSchedule[i].enabled
            ?"true"
            :"false"
        )+
        "}";
json+=",";
json+="]}";
server.send(
      200,
      "application/json",
      json
    );
```


### `/syringeB/dispense` — `handleSyrBDispense`

```cpp
server.send(200, "application/json", "{\"dispensed\":true}");
server.send(409, "application/json", "{\"dispensed\":false,\"reason\":\"" + reason +
        "\",\"next_eligible_at\":\"" + formatDeviceEpoch(nextChemicalEligibleEpoch()) + "\"}");
```


### `/syringeB/test-dispense` — `handleSyrBTestDispense`

```cpp
server.send(200, "application/json", "{\"dispensed\":true}");
server.send(409, "application/json", "{\"dispensed\":false,\"reason\":\"" + reason + "\"}");
```


### `/syringeB/refill-confirm` — `handleSyrBRefillConfirm`

```cpp
server.send(409, "application/json", "{\"refill_confirmed\":false,\"reason\":\"Pump busy or persistent state unavailable\"}");
server.send(503, "application/json", "{\"refill_confirmed\":false,\"reason\":\"Could not persist refill confirmation\"}");
server.send(200, "application/json", "{\"refill_confirmed\":true}");
```


### `/syringeB/stop` — `handleSyrBStop`

```cpp
server.send(
      200,
      "application/json",
      "{\"stopped\":true}"
    );
```


### `/syringeB/retract` — `handleSyrBRetract`

```cpp
server.send(
      200,
      "application/json",
      "{\"retracted\":true}"
    );
```


### `/syringeB/schedule` — `handleSyrBSchedule`

```cpp
server.send(400, "application/json", "{\"schedule\":\"invalid\"}");
server.send(503, "application/json", "{\"schedule\":\"not_saved\"}");
server.send(503, "application/json", "{\"schedule\":\"marker_reset_failed\"}");
server.send(200, "application/json", "{\"schedule\":\"saved\"}");
```


### `/ph/auto/status` — `handlePhAutoStatus`

```cpp
String json="{";
json +=
      "\"enabled\":"+
      String(
        phAutoDoseEnabled
          ?"true"
          :"false"
      )+",";
json +=
      "\"target_min\":"+
      String(
        phTargetMin,
        2
      )+",";
json +=
      "\"target_max\":"+
      String(
        phTargetMax,
        2
      )+",";
json +=
      "\"cooldown_ms\":"+
      String(
        phDoseCooldownMs
      )+",";
json +=
      "\"cooldown_remaining_ms\":"+
      String(
        remaining
      )+",";
json += "\"clock_synced\":" + String(deviceClockSynchronized() ? "true" : "false") + ",";
json += "\"next_eligible_at\":\"" + formatDeviceEpoch(nextChemicalEligibleEpoch()) + "\",";
json +=
      "\"last_action\":\""+
      phAutoLastAction+
      "\"";
json+="}";
server.send(
      200,
      "application/json",
      json
    );
```


### `/ph/auto/config` — `handlePhAutoConfig`

```cpp
server.send(503, "application/json", "{\"config\":\"not_saved\"}");
server.send(
      200,
      "application/json",
      "{\"config\":\"saved\"}"
    );
```


### `/demo/status` — `handleDemoStatus`

```cpp
String json="{";
json +=
      "\"demo_mode\":"+
      String(
        demoMode
          ?"true"
          :"false"
      )+",";
json +=
      "\"demo_ph\":"+
      String(
        demoPhValue,
        2
      );
json+="}";
server.send(
      200,
      "application/json",
      json
    );
```


### `/demo/ph` — `handleDemoPh`

```cpp
server.send(
      200,
      "application/json",
      "{\"demo_ph\":\"set\"}"
    );
```


### `/demo/mode` — `handleDemoMode`

```cpp
server.send(
      200,
      "application/json",
      "{\"demo_mode\":\"set\"}"
    );
```


### `/uv/status` — `handleUvStatus`

```cpp
String json="{";
json +=
      "\"led_on\":"+
      String(
        uvState
          ?"true"
          :"false"
      )+",";
json +=
      "\"remaining_ms\":"+
      String(
        remaining
      )+",";
json +=
      "\"total_on_ms\":"+
      String(
        uvTotalOnMs
      )+",";
json +=
      "\"schedule_enabled\":"+
      String(
        uvScheduleEnabled
          ?"true"
          :"false"
      )+",";
json +=
      "\"sched_on\":\""+
      String(sOn)+
      "\",";
json +=
      "\"sched_off\":\""+
      String(sOff)+
      "\"";
json+="}";
server.send(
      200,
      "application/json",
      json
    );
```


### `/uv/on` — `handleUvOn`

```cpp
server.send(
      200,
      "application/json",
      "{\"led\":\"on\"}"
    );
```


### `/uv/off` — `handleUvOff`

```cpp
server.send(
      200,
      "application/json",
      "{\"led\":\"off\"}"
    );
```


### `/uv/timer` — `handleUvTimer`

```cpp
server.send(
        200,
        "application/json",
        "{\"led\":\"timer\"}"
      );
server.send(
        400,
        "application/json",
        "{\"error\":\"missing duration\"}"
      );
```


### `/uv/schedule` — `handleUvSchedule`

```cpp
server.send(503, "application/json", "{\"schedule\":\"not_saved\"}");
server.send(
      200,
      "application/json",
      "{\"schedule\":\"saved\"}"
    );
```


### `/led/status` — `handleLedStatus`

```cpp
String json="{";
json +=
      "\"led_on\":"+
      String(
        ledState
          ?"true"
          :"false"
      )+",";
json +=
      "\"remaining_ms\":"+
      String(
        remaining
      )+",";
json +=
      "\"total_on_ms\":"+
      String(
        ledTotalOnMs
      )+",";
json +=
      "\"schedule_enabled\":"+
      String(
        ledScheduleEnabled
          ?"true"
          :"false"
      )+",";
json +=
      "\"sched_on\":\""+
      String(sOn)+
      "\",";
json +=
      "\"sched_off\":\""+
      String(sOff)+
      "\"";
json+="}";
server.send(
      200,
      "application/json",
      json
    );
```


### `/led/on` — `handleLedOn`

```cpp
server.send(
      200,
      "application/json",
      "{\"led\":\"on\"}"
    );
```


### `/led/off` — `handleLedOff`

```cpp
server.send(
      200,
      "application/json",
      "{\"led\":\"off\"}"
    );
```


### `/led/timer` — `handleLedTimer`

```cpp
server.send(
        200,
        "application/json",
        "{\"led\":\"timer\"}"
      );
server.send(
        400,
        "application/json",
        "{\"error\":\"missing duration\"}"
      );
```


### `/led/schedule` — `handleLedSchedule`

```cpp
server.send(503, "application/json", "{\"schedule\":\"not_saved\"}");
server.send(
      200,
      "application/json",
      "{\"schedule\":\"saved\"}"
    );
```

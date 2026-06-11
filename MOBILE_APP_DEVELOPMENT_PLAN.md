# AquaLogic Mobile App Development Plan

## Goal

Build AquaLogic as a real Android mobile app where the phone provides the main user interface and the ESP32 acts as the hardware controller for sensors and aquarium devices.

The ESP32 should not store the full app or a heavy website. It should only read sensors, control hardware, and expose small API endpoints that the Android app can call over Wi-Fi.

## Recommended Architecture

```txt
Android App
  |
  | Wi-Fi HTTP requests
  v
ESP32 Controller
  |
  | sensors, relays, LCD, pumps, feeder, lights
  v
Aquarium Hardware
```

Later, AquaLogic can grow into this stronger architecture:

```txt
Android App <-> Backend / Database <-> ESP32 Controller
```

This future version would support user accounts, cloud history, backups, multiple phones, remote access, and richer analytics.

## Track 1: ESP32 API

The ESP32 is responsible for the physical aquarium system. It should stay lightweight and focused on hardware.

### Responsibilities

- Read water sensor values.
- Evaluate basic sensor status.
- Control aquarium hardware.
- Return live data to the Android app.
- Accept control commands from the Android app.
- Keep the temporary embedded dashboard only if useful for debugging.

### Current Sensors

- Temperature sensor
- Turbidity sensor
- TDS sensor

### Possible Future Sensors

- pH sensor
- Water level sensor
- Dissolved oxygen sensor

### Suggested API Endpoints

```txt
GET  /data
GET  /status
POST /light/on
POST /light/off
POST /feeder/run
POST /pump/on
POST /pump/off
POST /settings
```

### Example Data Response

```json
{
  "temp_c": 27.4,
  "temp_status": "NORMAL",
  "turbidity_raw": 2300,
  "turbidity_status": "CLEAR",
  "tds_raw": 950,
  "tds_status": "NORMAL",
  "overall_status": "GOOD"
}
```

### ESP32 Notes

- Avoid storing a large website on the ESP32.
- Avoid large images, fonts, and frontend libraries.
- Keep API responses small.
- Avoid long blocking delays where possible, because they can make web requests slow.
- Move Wi-Fi credentials out of public code before sharing or pushing updates.

## Track 2: Android App

The Android app is the real AquaLogic user experience. It handles the interface, navigation, controls, and user-facing logic.

### Recommended Stack

Use React Native with Expo unless the project requires native Kotlin/Java.

Expo is recommended because it is faster for UI development, easier to test on one Android phone, and suitable for building a polished prototype.

### Core Screens

- Dashboard
- Controls
- Alerts
- History
- Fish / Tank Info
- Settings
- ESP32 Connection Setup

### Dashboard

The Dashboard should show the current aquarium condition at a glance.

Suggested content:

- Overall water status
- Temperature card
- Turbidity card
- TDS card
- Last updated time
- ESP32 connection state
- Warning banner when readings are unsafe

### Controls

The Controls screen should allow manual hardware actions.

Suggested controls:

- Toggle aquarium light
- Run feeder
- Start or stop pump
- Emergency stop
- Optional chemical dispenser controls
- Optional water replacement controls

### Alerts

The Alerts screen should show unsafe or unusual conditions.

Suggested alert types:

- High temperature
- Low temperature
- Dirty water
- High TDS
- Sensor disconnected
- ESP32 offline

### History

The History screen can start simple and grow later.

Prototype version:

- Store recent readings locally on the phone.
- Show simple reading logs.
- Add basic charts later.

Future version:

- Store readings in a backend database.
- Support daily, weekly, and monthly charts.
- Export reports if needed.

### Fish / Tank Info

This section can manage aquarium and fish data.

Suggested content:

- Tank profile
- Fish species
- Fish count
- Ideal water ranges
- Feeding schedule
- Maintenance notes

### Settings

Suggested settings:

- ESP32 IP address
- Sensor thresholds
- Refresh interval
- Alert preferences
- Manual or automatic mode

## Track 3: Storage

Storage should grow with the project.

### Prototype Storage

For the first version, store data locally on the Android phone.

Suggested local data:

- ESP32 IP address
- User settings
- Tank profile
- Fish records
- Recent sensor history

### Future Backend Storage

For a more complete system, use a backend and database.

Suggested backend data:

- User accounts
- Multiple tanks
- Long-term sensor history
- Alerts and logs
- Fish records
- Maintenance records
- Device registration

The existing `backend` folder in this workspace can become the starting point for this future version.

## Development Milestones

### Milestone 1: Planning and Design

- Confirm app screens.
- Review the UI reference.
- Decide visual style and navigation.
- Decide which hardware controls are actually connected.

### Milestone 2: App Prototype with Demo Data

- Create the Android app project.
- Build the main navigation.
- Build the dashboard UI.
- Use fake/demo sensor data first.
- Test layout on the Android phone.

### Milestone 3: ESP32 Connection

- Add ESP32 IP address setting.
- Connect the app to `GET /data`.
- Show real sensor readings in the dashboard.
- Display online/offline status.

### Milestone 4: Hardware Controls

- Add ESP32 command endpoints.
- Add app buttons for light, feeder, pump, and stop actions.
- Test each command with the actual hardware.
- Add loading, success, and error states.

### Milestone 5: Local Storage and History

- Save app settings locally.
- Save recent sensor readings locally.
- Add a basic history screen.
- Add simple alert records.

### Milestone 6: Polish and Demo Readiness

- Improve mobile UI based on the reference design.
- Add clear empty, loading, offline, warning, and error states.
- Prepare demo mode in case hardware connection fails during presentation.
- Document setup instructions.

## Immediate Next Steps

1. Share the UI reference.
2. Identify which hardware controls are already wired or planned.
3. Decide whether the app will use Expo or native Android.
4. Update the ESP32 sketch to behave more like an API device.
5. Start the Android app with demo data before connecting real hardware.

# AquaLogic Mobile App

Android-first Flutter staff dashboard prototype for AquaLogic.

## Current status

The app authenticates against the AquaLogic FastAPI service (Railway in release
builds) and reads live fleet, tank, alert, monitoring-incident, species, and
read-only equipment data, plus authenticated Android push registration and
notification navigation. Mock repositories remain injectable for tests and for
features without a live API (recent activity, sensor-history charts, profile
editing, and real actuator commands). The app never connects to ESP32 hardware
directly.

Debug builds default to the Android emulator host alias (`10.0.2.2:8000`); pass
`--dart-define=AQUALOGIC_API_BASE_URL=...` to point a debug build elsewhere.

## Development

### Chrome UI preview

Use the explicit preview entry point to inspect the UI without running a backend:

```powershell
flutter run -d chrome -t lib/main_preview.dart
```

Sign in with either development-only account:

| Role | Email | Password |
| --- | --- | --- |
| Owner | `owner@aqualogic.local` | `owner123` |
| Staff | `staff@aqualogic.local` | `staff123` |

The preview displays a **SIMULATED UI** banner and selects the existing mock
repositories. It uses no Railway credentials, Firebase push, or hardware.
Open **More → Tank Console → Enter Console Mode** to review the console. Resize
the browser to a wide phone-sized viewport; Android orientation/immersive/awake
behavior requires physical-device verification.

This preview is separate from real authentication. The native session code reads
refresh-cookie response headers and sends the refresh Cookie header directly;
it is not a browser session implementation. Changing the API URL alone does not
make that flow compatible with Chrome.

### Normal development

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

See `../docs/areas/MOBILE.md` for the current boundary and integration notes.

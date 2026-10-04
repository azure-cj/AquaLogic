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

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

See `../docs/areas/MOBILE.md` for the current boundary and integration notes.

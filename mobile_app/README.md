# AquaLogic Mobile App

Android-first Flutter staff dashboard prototype for AquaLogic.

## Current status

The app currently uses local demo data for sensor readings, alerts, fish
information, and control interactions. It is not yet connected to the FastAPI
backend, does not authenticate users, and does not require ESP32 hardware.

## Development

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

See `../docs/areas/MOBILE.md` for the current boundary and integration notes.

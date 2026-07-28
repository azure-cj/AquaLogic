# Mobile Area Guide

Status: Flutter prototype
Last reviewed: 2026-07-27

## Read first

- [`../PROJECT_CONTEXT.md`](../PROJECT_CONTEXT.md)
- [`../ARCHITECTURE.md`](../ARCHITECTURE.md)
- [`../API_CONTRACT.md`](../API_CONTRACT.md)
- [`../MOBILE_APP_DEVELOPMENT_PLAN.md`](../MOBILE_APP_DEVELOPMENT_PLAN.md)

## Current boundary

The Flutter app is an Android-first staff dashboard prototype. Its readings,
alerts, fish data, and controls use local demo data. It has no HTTP client,
backend authentication, or live sensor connection yet.

Do not document or test it as an integrated backend client until those pieces
exist. When integration begins, update this guide, the API contract, and the
development status together.

## Important locations

- `mobile_app/lib/app/`: app composition, theme, navigation, and startup.
- `mobile_app/lib/features/`: home, tanks, sensors, alerts, fish, controls,
  and more screens.
- `mobile_app/lib/shared/`: shared models and widgets.
- `mobile_app/test/`: widget tests.
- `mobile_app/pubspec.yaml`: Flutter dependencies and assets.

## Common checks

```powershell
cd mobile_app
flutter pub get
flutter analyze
flutter test
```

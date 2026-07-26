# AquaLogic

AquaLogic is a smart aquarium monitoring and automation system for JRed Aquatics. It combines ESP32-based water sensing, a FastAPI backend, a Flutter staff mobile app prototype, and a React web application for staff operations and QR-accessible public tank pages.

The system is designed to help staff monitor water quality, manage tank and fish information, respond to alerts, and eventually control aquarium equipment such as feeding, lighting, filtration, chemical dosing, and partial water replacement.

## Current Status

This repository is in active prototype development. The current implementation is
software-first and local-first; live hardware integration is a later phase.

- ESP32 firmware: initial Arduino sketch and sensor libraries are included.
- Backend: FastAPI foundation is included with database models, auth, tank/fish/sensor/alert endpoints, seed scripts, and tests.
- Staff mobile app: Flutter Android-first prototype is included with dashboard, tanks, tank detail, controls, alerts, fish library, splash screen, and app icon.
- Web app: React customer/public pages and the staff/admin dashboard are implemented under `web/`.
- Hardware integration: planned after mock data, backend, mobile app, and public web flows are stable.

## Features

### IoT and Automation

- ESP32 sensor collection for aquarium water conditions.
- Planned monitoring for temperature, pH, turbidity, dissolved oxygen, TDS, and ammonia.
- Planned actuator controls for feeding, lighting, filtration/UV sterilization, chemical dosing, and partial water replacement.
- Local Wi-Fi communication with backend services.

### Backend API

- FastAPI application with SQLAlchemy models and Alembic migrations.
- Staff JWT authentication.
- Tank and fish species management.
- Tank-fish assignment endpoints.
- Sensor reading persistence.
- Alert listing and resolution.
- Public tank endpoint for QR pages.

### Staff Mobile App

- Flutter Android-first staff dashboard.
- Home screen with system health and live readings.
- Tank overview and tank detail screens.
- Demo controls panel.
- Alerts screen with recommendations.
- Fish library with search.
- AquaLogic app icon and startup splash scene.

### Web App

AquaLogic includes a React + TypeScript web app for staff operations and public
customer pages. The public experience provides mobile-first tank pages that can
be opened from QR codes displayed near tanks.

Public route:

```text
/tank/:publicId
```

Backend API:

```text
GET /public/tanks/{public_id}
```

The customer page shows tank name, location, water status, fish species cards,
care notes, and AquaLogic branding. Customers do not need accounts or login.

## Repository Structure

```text
AquaLogic/
  Aqualogic.ino                 # ESP32/Arduino firmware
  backend/                      # FastAPI backend
  mobile_app/                   # Flutter staff mobile app
  docs/                         # Canonical context, plans, and implementation notes
  DallasTemperature/            # Arduino library dependency
  DIYables_LCD_I2C/             # Arduino library dependency
  LiquidCrystal_I2C/            # Arduino library dependency
  OneWire/                      # Arduino library dependency
  web/                          # React public tank pages and staff/admin dashboard
```

The Flutter app currently uses local demo data and is not yet connected to the
backend API. The firmware is also not a prerequisite for local software work.

## Quick Start

### Mobile App

```powershell
cd mobile_app

flutter pub get
flutter analyze
flutter test
flutter run
```

### Backend

```powershell
cd backend

python -m venv .venv
.\.venv\Scripts\activate
pip install -r requirements.txt
copy .env.example .env
alembic upgrade head
python -m seed.seed_data
uvicorn app.main:app --reload
```

API docs:

```text
http://127.0.0.1:8000/docs
http://127.0.0.1:8000/redoc
```

Backend tests:

```powershell
cd backend
pytest -q
```

### ESP32 Firmware

Open `Aqualogic.ino` in the Arduino IDE and make sure the included library folders are available to the sketch:

- `DallasTemperature/`
- `DIYables_LCD_I2C/`
- `LiquidCrystal_I2C/`
- `OneWire/`

Hardware integration is still planned, so mobile and backend development currently use mock/sample data.

## Development Roadmap

1. Backend foundation, seed data, authentication, and API contract.
2. Rule-based status/alert flow and optional demo sensor ingestion.
3. React public tank pages and staff/admin dashboard stabilization.
4. Flutter staff app integration with the backend.
5. ESP32 hardware integration and Raspberry Pi deployment.

## Documentation

Start with the workspace instructions and documentation index:

- `AGENTS.md`
- `docs/INDEX.md`
- `docs/DEVELOPMENT_STATUS.md`
- `docs/ARCHITECTURE.md`
- `docs/API_CONTRACT.md`
- `docs/WORKFLOWS.md`

Historical and planning documents are also preserved in `docs/`:

- `docs/AQUALOGIC_CONTEXT.md`
- `docs/AquaLogic_Full_Software_Development_Plan.md`
- `docs/AquaLogic_Implementation_Plan.md`
- `docs/MOBILE_APP_DEVELOPMENT_PLAN.md`
- `docs/WEB_DASHBOARD_IMPLEMENTATION_REPORT.md`

## Scope Notes

Out of scope for the current version:

- Customer accounts or login.
- E-commerce.
- Multi-branch support.
- iOS release.
- Cloud hosting.
- Machine-learning predictions.

The intended first deployment path is local-first: FastAPI backend during development, then Raspberry Pi deployment when hardware integration begins.

# AquaLogic

AquaLogic is a smart aquarium monitoring and automation system for JRed Aquatics. It combines ESP32-based water sensing, a FastAPI backend, a Flutter staff mobile app, and a planned customer-facing React web app for QR-accessible tank pages.

The system is designed to help staff monitor water quality, manage tank and fish information, respond to alerts, and eventually control aquarium equipment such as feeding, lighting, filtration, chemical dosing, and partial water replacement.

## Current Status

This repository is in active prototype development.

- ESP32 firmware: initial Arduino sketch and sensor libraries are included.
- Backend: FastAPI foundation is included with database models, auth, tank/fish/sensor/alert endpoints, seed scripts, and tests.
- Staff mobile app: Flutter Android-first prototype is included with dashboard, tanks, tank detail, controls, alerts, fish library, splash screen, and app icon.
- Customer web app: planned, not yet implemented.
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
- Public tank endpoint for future QR pages.

### Staff Mobile App

- Flutter Android-first staff dashboard.
- Home screen with system health and live readings.
- Tank overview and tank detail screens.
- Demo controls panel.
- Alerts screen with recommendations.
- Fish library with search.
- AquaLogic app icon and startup splash scene.

### Planned Customer Web App

AquaLogic will include a public React + Tailwind web app for customers. The web app will provide mobile-first tank pages that can be opened from QR codes displayed near tanks.

Planned route:

```text
/tank/:id
```

Planned backend API:

```text
GET /public/tanks/{id}
```

The customer page will show tank name, location, water status, fish species cards, care notes, and AquaLogic branding. Customers will not need accounts or login. This should be developed after the backend public tank endpoint and fish/tank seed data are stable.

## Repository Structure

```text
AquaLogic/
  Aqualogic.ino                 # ESP32/Arduino firmware
  backend/                      # FastAPI backend
  mobile_app/                   # Flutter staff mobile app
  docs/                         # Project plans and context documents
  DallasTemperature/            # Arduino library dependency
  DIYables_LCD_I2C/             # Arduino library dependency
  LiquidCrystal_I2C/            # Arduino library dependency
  OneWire/                      # Arduino library dependency
  customer-web/                 # Planned React + Tailwind public QR pages
```

`customer-web/` is listed as planned architecture and does not exist yet.

## Quick Start

### Mobile App

```powershell
cd mobile_app

& 'C:\Users\admin\devtools\flutter\bin\flutter.bat' pub get
& 'C:\Users\admin\devtools\flutter\bin\flutter.bat' analyze
& 'C:\Users\admin\devtools\flutter\bin\flutter.bat' test
& 'C:\Users\admin\devtools\flutter\bin\flutter.bat' run -d "adb-93419779-vLKFy6._adb-tls-connect._tcp"
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

1. Backend foundation and seed data.
2. Mock sensor flow and rule-based alert decision engine.
3. Customer React web pages for QR-accessible tank views.
4. Flutter staff app core with login, tank overview, and tank detail.
5. Flutter fish management.
6. Flutter alerts and controls.
7. ESP32 hardware integration and Raspberry Pi deployment.

The best time to build `customer-web/` is after the backend public tank endpoint and realistic sample fish/tank data are stable. Building it then will avoid reworking the web app around changing API shapes.

## Documentation

Project planning and context documents live in `docs/`:

- `docs/AQUALOGIC_CONTEXT.md`
- `docs/AquaLogic_Full_Software_Development_Plan.md`
- `docs/AquaLogic_Implementation_Plan.md`
- `docs/MOBILE_APP_DEVELOPMENT_PLAN.md`

## Scope Notes

Out of scope for the current version:

- Customer accounts or login.
- E-commerce.
- Multi-branch support.
- iOS release.
- Cloud hosting.
- Machine-learning predictions.

The intended first deployment path is local-first: FastAPI backend during development, then Raspberry Pi deployment when hardware integration begins.

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

### Prerequisites

For the local web and API development environment, install:

- Git
- Node.js 20 LTS or newer, which includes `npm`
- Python 3.11 or newer
- Flutter SDK only if you will work on `mobile_app/`
- Arduino IDE only if you will work on the ESP32 firmware

Check the installations from PowerShell:

```powershell
git --version
node --version
npm --version
python --version
```

If `npm` is missing, install Node.js from <https://nodejs.org/> and choose the
LTS version. After installation, close and reopen PowerShell, then run the
version checks again. The repository already contains `web/package-lock.json`,
so teammates should use `npm ci` to install the exact web dependencies.

### Recommended first-time setup

From the repository root (`AquaLogic/`):

```powershell
# Install the web dependencies
cd web
npm ci
npm run typecheck
npm test
cd ..

# Create and prepare the backend environment
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r requirements.txt
Copy-Item .env.example .env
alembic upgrade head
python -m seed.seed_data
cd ..
```

If PowerShell blocks virtual-environment activation, run this once in an
Administrator PowerShell or use the activation command shown by Python:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

### Start the local web and API

The simplest Windows workflow is to double-click `start-dev.bat` from the
repository root. It opens separate terminals for the API and web app.

For manual startup, use two PowerShell windows:

**Terminal 1 — backend API**

```powershell
cd backend
.\.venv\Scripts\Activate.ps1
$env:DATABASE_URL = 'sqlite:///./aqualogic.db'
$env:DEMO_SENSOR_ENABLED = 'true'
$env:DEMO_SENSOR_INSTANCE = 'true'
$env:DEMO_SENSOR_INTERVAL_SECONDS = '30'
alembic upgrade head
python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

**Terminal 2 — React web app**

```powershell
cd web
npm run dev
```

Open these addresses in a browser:

- Staff web app: <http://localhost:5173/admin>
- API documentation: <http://127.0.0.1:8000/docs>
- API alternative documentation: <http://127.0.0.1:8000/redoc>

The demo sensor environment variables create simulated readings for local
testing. They do not connect to the ESP32 hardware.

### If a teammate only needs to inspect the project

They still need Node.js and the npm dependencies to run the web app locally.
After cloning or pulling the repository, they should run:

```powershell
cd AquaLogic\web
npm ci
npm run dev
```

If they only need to read the source, review the screenshots, or inspect the
documentation, no npm installation is required. If they need a live page but
cannot install Node.js, use a shared development machine or screen-share the
running app; the repository does not currently include a self-contained web
runtime or hosted preview.

### Common development checks

```powershell
# Web checks
cd web
npm run typecheck
npm test
npm run build

# Backend checks
cd ..\backend
.\.venv\Scripts\Activate.ps1
pytest -q
```

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

# AquaLogic — Full Software Development Plan

---

## Project Overview

**Goal:** Build the software side of AquaLogic in three parts — a FastAPI backend, a Flutter staff mobile app (Android-first), and a React customer-facing web app — all sharing one database and one API.

**Current constraint:** No hardware yet. All sensor data will be mocked during development. Hardware integration comes last.

**Client:** JRed Aquatics, ~7-10 tanks, ornamental fish breeding and sales.

---

## Final Tech Stack

| Layer | Technology | Notes |
|---|---|---|
| Backend | FastAPI (Python) | Runs locally during dev, Raspberry Pi later |
| Database | SQLite → PostgreSQL | SQLite for dev simplicity, migrate when deploying to Pi |
| ORM | SQLAlchemy + Alembic | Alembic handles migrations cleanly |
| Auth | JWT (JSON Web Tokens) | Staff login only, customers have no auth |
| Real-time | WebSockets (FastAPI native) | Live sensor streaming to Flutter |
| Mock Data | Python script | Simulates sensor readings per tank |
| Staff App | Flutter (Dart) | Android-first, iOS later |
| Customer Web | React + Tailwind CSS | Public, mobile-first, QR-accessible |
| State (Flutter) | Riverpod | Clean, scalable state management |
| HTTP (Flutter) | Dio | API calls from Flutter |
| Hosting (dev) | Local machine (localhost) | Move to Raspberry Pi when hardware arrives |
| Domain | TBD (real domain later) | Placeholder local URLs for now |

---

## Repository Structure

```
aqualogic/
├── backend/                  # FastAPI
│   ├── app/
│   │   ├── main.py
│   │   ├── database.py
│   │   ├── models/
│   │   │   ├── tank.py
│   │   │   ├── fish.py
│   │   │   ├── sensor.py
│   │   │   ├── alert.py
│   │   │   └── user.py
│   │   ├── routes/
│   │   │   ├── tanks.py
│   │   │   ├── fish.py
│   │   │   ├── sensors.py
│   │   │   ├── alerts.py
│   │   │   └── auth.py
│   │   ├── schemas/          # Pydantic schemas
│   │   ├── services/         # Business logic
│   │   │   └── decision_engine.py  # Rule-based alerts
│   │   └── websockets/
│   │       └── sensor_stream.py
│   ├── seed/
│   │   ├── seed_fish.py      # Sample fish data
│   │   ├── seed_tanks.py     # Sample tank data
│   │   └── mock_sensor.py    # Continuous mock sensor generator
│   ├── alembic/              # DB migrations
│   └── requirements.txt
│
├── customer-web/             # React + Tailwind
│   ├── src/
│   │   ├── pages/
│   │   │   └── TankPage.jsx  # /tank/:id
│   │   ├── components/
│   │   │   ├── FishCard.jsx
│   │   │   ├── ParameterBadge.jsx
│   │   │   └── TankHeader.jsx
│   │   └── api/
│   │       └── client.js
│   └── package.json
│
└── staff-app/                # Flutter
    ├── lib/
    │   ├── main.dart
    │   ├── models/
    │   ├── providers/        # Riverpod
    │   ├── screens/
    │   │   ├── login/
    │   │   ├── tank_overview/
    │   │   ├── tank_detail/
    │   │   ├── fish_management/
    │   │   ├── alerts/
    │   │   └── controls/
    │   ├── services/
    │   │   ├── api_service.dart
    │   │   └── websocket_service.dart
    │   └── widgets/
    └── pubspec.yaml
```

---

## Data Model

### Tank
```
id              INTEGER PRIMARY KEY
name            TEXT (e.g. "Tank A", "Tank 3")
location        TEXT (e.g. "Front display", "Breeding room")
description     TEXT
created_at      DATETIME
```

### FishSpecies
```
id                  INTEGER PRIMARY KEY
common_name         TEXT
scientific_name     TEXT
photo_url           TEXT
description         TEXT
ideal_temp_min      FLOAT
ideal_temp_max      FLOAT
ideal_ph_min        FLOAT
ideal_ph_max        FLOAT
ideal_do_min        FLOAT
ideal_tds_min       FLOAT
ideal_tds_max       FLOAT
diet                TEXT
compatibility_notes TEXT
care_tips           TEXT
created_at          DATETIME
```

### TankFish (junction)
```
tank_id         FK → Tank
fish_species_id FK → FishSpecies
added_at        DATETIME
```

### SensorReading
```
id                  INTEGER PRIMARY KEY
tank_id             FK → Tank
timestamp           DATETIME
temperature         FLOAT
ph                  FLOAT
turbidity           FLOAT (NTU)
dissolved_oxygen    FLOAT (mg/L)
tds                 FLOAT (ppm)
ammonia             FLOAT (ppm)
is_mock             BOOLEAN
```

### Alert
```
id              INTEGER PRIMARY KEY
tank_id         FK → Tank
reading_id      FK → SensorReading
parameter       TEXT (e.g. "ph", "ammonia")
severity        ENUM (warning, critical)
message         TEXT
is_resolved     BOOLEAN
created_at      DATETIME
```

### User (staff only)
```
id              INTEGER PRIMARY KEY
name            TEXT
email           TEXT UNIQUE
hashed_password TEXT
role            TEXT (default: "staff")
created_at      DATETIME
```

---

## API Endpoints

### Auth
```
POST   /auth/login          → returns JWT token
POST   /auth/logout
GET    /auth/me             → current user info
```

### Tanks
```
GET    /tanks               → list all tanks
GET    /tanks/:id           → tank detail + assigned fish
POST   /tanks               → create tank (staff)
PUT    /tanks/:id           → update tank (staff)
DELETE /tanks/:id           → delete tank (staff)
```

### Fish Species
```
GET    /fish                → list all species
GET    /fish/:id            → species detail
POST   /fish                → add species (staff)
PUT    /fish/:id            → update species (staff)
DELETE /fish/:id           → delete species (staff)
```

### Tank-Fish Assignment
```
POST   /tanks/:id/fish      → assign fish to tank (staff)
DELETE /tanks/:id/fish/:fid → remove fish from tank (staff)
```

### Sensors
```
GET    /tanks/:id/sensors           → latest reading for tank
GET    /tanks/:id/sensors/history   → historical readings (with date filter)
POST   /tanks/:id/sensors           → post new reading (ESP32 later, mock now)
```

### Alerts
```
GET    /alerts                      → all unresolved alerts
GET    /tanks/:id/alerts            → alerts for specific tank
PUT    /alerts/:id/resolve          → mark alert resolved (staff)
```

### WebSocket
```
WS     /ws/tanks/:id/sensors        → live sensor stream for a tank
```

### Customer (Public, No Auth)
```
GET    /public/tanks/:id            → tank info + all fish species (for QR page)
```

---

## Decision Engine (Rule-Based)

Runs server-side every time a sensor reading comes in. Checks each parameter against safe thresholds and auto-generates alerts.

### Default Thresholds (Adjustable Later)
```
Temperature:       18°C – 30°C
pH:                6.5 – 8.5
Dissolved Oxygen:  > 5.0 mg/L
Turbidity:         < 10 NTU
TDS:               50 – 500 ppm
Ammonia:           < 0.5 ppm
```

### Logic
- If reading is outside range → generate **warning** alert
- If reading is critically outside range (e.g. ammonia > 1.0) → generate **critical** alert
- If alert for same parameter on same tank is already unresolved → don't duplicate
- Later: compare against species-specific requirements from FishSpecies table

---

## Mock Sensor Generator

A Python script that runs alongside the backend during development. Every 30 seconds it posts a simulated reading for each tank to the sensor endpoint. Readings are randomized within realistic ranges with occasional out-of-range spikes to test the alert system.

```
mock_sensor.py
├── Loops through all tanks
├── Generates realistic random readings
├── Occasionally spikes a value (to test alerts)
├── POSTs to /tanks/:id/sensors
└── Runs every 30 seconds
```

---

## Seed Data Plan

Since we don't have real JRed data yet, we seed with:

**7 Sample Tanks**
- Tank A through Tank G
- Mix of locations (Front Display, Breeding Room, etc.)

**15 Sample Fish Species** (common ornamental fish)
- Betta (Siamese Fighting Fish)
- Guppy
- Goldfish
- Koi
- Neon Tetra
- Angelfish
- Discus
- Molly
- Platy
- Swordtail
- Corydoras Catfish
- Zebra Danio
- Oscar
- Cherry Barb
- Clownfish

All with realistic water parameter ranges, diet info, and care tips. Replace with real JRed data after client meeting.

---

## Flutter Staff App — Screens

### 1. Login Screen
- Email + password fields
- JWT stored securely on device
- Redirects to Tank Overview on success

### 2. Tank Overview (Home)
- Grid or list of all tanks
- Each tank card shows: name, location, quick health status (green/yellow/red), unresolved alert count
- Tap to go to Tank Detail

### 3. Tank Detail
- Tank name and location
- Live sensor readings (6 parameter cards, color-coded by status)
- Real-time updates via WebSocket
- List of fish species in this tank (tap to view fish detail)
- Unresolved alerts for this tank
- Manual controls section (buttons: Feed Now, Toggle Lighting, etc.)

### 4. Fish Management
- List of all fish species
- Search and filter
- Tap to view/edit species
- Add new species (form with all fields + photo upload)
- Assign/remove fish from tanks

### 5. Alerts Screen
- All unresolved alerts across all tanks
- Filter by tank, severity
- Mark as resolved

### 6. Schedule Screen (Phase 2)
- Set feeding schedule per tank
- Set lighting schedule
- Placeholder for now, wired to hardware later

---

## Customer Web App — Screens

### Tank Page (`/tank/:id`)
Single page, loaded via QR scan.

**Layout (mobile-first):**
- Tank name and location header
- Current water status banner (general health — Good / Needs Attention)
- Fish species cards — one per species in the tank
  - Photo
  - Common name + scientific name
  - Brief description
  - Water requirements (temp, pH)
  - Diet
  - Care tips
- AquaLogic branding footer

**Design goals:** Fast load, no navigation needed, readable on any phone without zooming.

---

## Build Phases

### Phase 1 — Backend Foundation
**Output:** Running FastAPI server with database, all models, all endpoints, JWT auth, seed data loaded.

Tasks:
- Set up FastAPI project structure
- Define SQLAlchemy models
- Set up Alembic migrations
- Implement all CRUD endpoints
- Implement JWT auth
- Write and run seed scripts
- Test all endpoints via Swagger UI (FastAPI auto-generates this)

---

### Phase 2 — Mock Sensor System + Decision Engine
**Output:** Sensor data flowing automatically, alerts being generated.

Tasks:
- Build mock sensor generator script
- Implement decision engine (threshold checking, alert generation)
- Implement WebSocket endpoint for live streaming
- Test alert generation with spiked mock data

---

### Phase 3 — Customer Web Pages (React)
**Output:** Working public `/tank/:id` pages, QR-ready.

Tasks:
- Set up React + Tailwind project
- Build TankPage with API integration
- Build FishCard, ParameterBadge components
- Mobile responsiveness pass
- Test QR scan flow on actual phone

---

### Phase 4 — Flutter App: Core (Login + Tank Overview + Tank Detail)
**Output:** Staff can log in, see all tanks, and view live sensor data.

Tasks:
- Set up Flutter project with Riverpod + Dio
- Implement JWT login and secure token storage
- Build Tank Overview screen
- Build Tank Detail screen with WebSocket live data
- Color-coded sensor parameter cards

---

### Phase 5 — Flutter App: Fish Management
**Output:** Staff can add, edit, and assign fish species to tanks.

Tasks:
- Fish species list screen with search
- Add/edit fish species form
- Photo upload
- Tank assignment UI

---

### Phase 6 — Flutter App: Alerts + Controls
**Output:** Staff can monitor and resolve alerts, trigger manual controls.

Tasks:
- Alerts screen with filter
- Mark resolved functionality
- Manual control buttons (Feed, Light toggle — backend stubs for now)
- Push notification setup (basic, for critical alerts)

---

### Phase 7 — Hardware Integration
**Output:** Real ESP32 sensor data replaces mock data.

Tasks:
- Replace mock POST calls with real ESP32 data
- Calibrate thresholds based on real readings
- Test WebSocket streaming with real data
- Deploy backend to Raspberry Pi
- Final QA pass

---

## What's Deliberately Out of Scope
- Multi-branch support
- Customer accounts or login
- E-commerce
- iOS build (Android first, iOS later)
- Cloud hosting (local only for now)
- Advanced ML-based predictions (rule-based engine only)
- Long-term maintenance beyond project timeline

---

## Summary Timeline Alignment

Based on the paper's March–October 2026 timeline:

| Month | Focus |
|---|---|
| March–April | Planning (done), Phase 1 backend |
| May | Phase 2 mock sensors + Phase 3 customer web |
| June | Phase 4 Flutter core |
| July | Phase 5 Flutter fish management |
| August | Phase 6 Flutter alerts + controls |
| September | Phase 7 hardware integration |
| October | Testing, deployment, documentation |

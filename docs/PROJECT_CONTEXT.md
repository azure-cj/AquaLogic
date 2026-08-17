# AquaLogic Project Context

Status: Current product context
Last reviewed: 2026-08-15

## Purpose

AquaLogic helps JRed Aquatics monitor aquarium health, manage tank and fish
information, respond to water-quality alerts, and eventually control aquarium
equipment. The first useful product is software-first and local-first so staff
can validate operations before the ESP32 hardware deployment is complete.

## Users

- Staff monitor tanks, sensor readings, alerts, fish information, and customer
  assignments.
- Administrators manage staff accounts, thresholds, customers, and operational
  settings.
- Customers and visitors can view selected public tank information through QR
  links without signing in.
- Future hardware operators will provide sensor readings and receive control
  commands through a controlled device integration boundary.

## Current product shape

- A FastAPI backend stores the shared operational data and exposes authenticated
  staff routes plus public tank routes.
- A React web application provides the public QR tank page and the staff/admin
  dashboard.
- A Flutter Android-first app provides a polished staff dashboard prototype with
  local demo readings and demo controls.
- The temporary ESP32 laptop bridge ingests four sensor values and supports
  admin-only UV, normal LED, fish-feeder, and guarded Pump A/B manual-test
  commands without exposing the ESP32 to the internet. Pump tests are limited
  to empty syringes or water; schedules and pH auto-dose remain deferred.

## Current scope

### In scope

- Staff authentication and password-change flow.
- Tank, fish species, tank-fish assignment, customer, and staff management.
- Sensor readings, configurable thresholds, rule-based alert generation, alert
  resolution, and operational analytics.
- Public, read-only tank pages suitable for QR labels.
- Local development, seeded demo data, and deployment preparation.

### Planned or deferred

- Connecting the Flutter app to the backend API.
- Additional hardware, production actuator safety interlocks, and richer
  automation workflows beyond the v1 bridge.
- Raspberry Pi deployment and production PostgreSQL validation.
- Scheduling, hardware safety interlocks, and richer automation workflows.
- Pagination and database-level analytics for larger fleets.

### Out of scope unless explicitly added

- E-commerce and inventory transactions.
- Customer accounts and customer editing access.
- Multi-branch operations.
- Machine-learning predictions.
- iOS release commitments.

## Constraints and conventions

- Development defaults to SQLite and local processes; PostgreSQL is the target
  for a production deployment path.
- The operational timezone is Asia/Manila unless a feature explicitly defines a
  different storage or display rule.
- Public pages must remain read-only and must not expose staff-only identifiers
  or controls.
- Sensor readings are the input to status and alert decisions. Thresholds are
  configurable through the backend and admin web flow.
- Actuator commands are admin-only, expire while queued, use a fixed
  server-side device-to-tank mapping, and travel through the local-only bridge;
  public pages and staff users never control hardware.
- Keep secrets and deployment credentials outside the repository.

## Terminology

- **Tank ID**: internal numeric database identifier used by staff APIs.
- **Public ID**: UUID-like identifier used in customer QR URLs.
- **Reading**: one timestamped set of temperature, pH, turbidity, dissolved
  oxygen, TDS, and ammonia values for a tank.
- **Alert**: a persisted warning or critical condition generated from a reading;
  it can remain active or be resolved by staff.
- **Demo sensor**: an optional backend process that generates readings for local
  development when both demo flags are enabled.

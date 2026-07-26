# AquaLogic API Contract

Status: Current route inventory
Last reviewed: 2026-07-27

The running FastAPI application at `backend/app/main.py` is the executable
contract. This document is a navigation aid; response models and tests remain
the final authority for exact fields and validation.

## Authentication

Authenticated routes use the bearer token returned by `POST /auth/login`.

| Method | Route | Access | Purpose |
| --- | --- | --- | --- |
| POST | `/auth/login` | Public | Authenticate an active user |
| POST | `/auth/logout` | Authenticated | Client-side JWT logout acknowledgement |
| GET | `/auth/me` | Authenticated | Read current user |
| POST | `/auth/change-password` | Authenticated | Complete or change password |

Temporary-password users are authenticated but must complete the password-change
flow before accessing dashboard operations.

## Core staff resources

| Method | Route | Purpose |
| --- | --- | --- |
| GET/POST | `/tanks` | List or create tanks |
| GET/PUT/DELETE | `/tanks/{tank_id}` | Read, update, or delete a tank |
| POST/DELETE | `/tanks/{tank_id}/fish` and `/tanks/{tank_id}/fish/{fish_id}` | Manage tank/species assignments |
| GET/POST | `/fish` | List or create fish species |
| GET/PUT/DELETE | `/fish/{fish_id}` | Read, update, or delete a species |
| GET | `/tanks/{tank_id}/sensors` | Read latest sensor data |
| GET | `/tanks/{tank_id}/sensors/history` | Read bounded sensor history |
| POST | `/tanks/{tank_id}/sensors` | Ingest a sensor reading |
| GET | `/alerts` | List active or all alerts |
| GET | `/alerts/history` | Filter alert history |
| GET | `/tanks/{tank_id}/alerts` | List alerts for a tank |
| PUT | `/alerts/{alert_id}/resolve` | Resolve an alert |

## Operations and administration

| Method | Route | Access | Purpose |
| --- | --- | --- | --- |
| GET | `/fleet` | Staff | Fleet overview and reporting state |
| GET | `/analytics/fleet` | Staff | Fleet/tank trends, historical threshold context, alert events, comparisons, and uptime |
| GET | `/thresholds` | Staff | Read threshold configuration |
| PUT | `/thresholds/{parameter}` | Admin | Update one parameter threshold |
| GET/POST | `/customers` | Staff | List or create customers |
| PUT/DELETE | `/customers/{customer_id}` | Staff | Update or delete customers |
| GET | `/users` | Admin | List staff users |
| POST | `/users` | Admin | Create a temporary-password user |
| PUT | `/users/{user_id}` | Admin | Update role or active state |
| POST | `/users/{user_id}/reset-password` | Admin | Issue a temporary password |

## Public route

| Method | Route | Access | Purpose |
| --- | --- | --- | --- |
| GET | `/public/tanks/{public_id}` | Public | Read a public QR tank view |

The public route only returns tanks marked public and uses the public identifier.
The web route consuming it is `/tank/:publicId`.

## Operational endpoints and notes

- `GET /health` is the deployment health check.
- CORS is configured from `CORS_ORIGINS`; production rejects wildcard CORS.
- Demo ingestion requires both `DEMO_SENSOR_ENABLED` and
  `DEMO_SENSOR_INSTANCE` to be enabled.
- Pagination is not yet available on the main list endpoints and is a known
  scaling limitation.
- Fish species responses include `category`, categorical `diet_type`, and the
  derived `tank_count`. Deleting a species with active tank assignments returns
  `409 Conflict`; assignments must be removed first.
- `GET /analytics/fleet` accepts `range=24h|7d|30d|custom`,
  `bucket=auto|15m|1h|6h|1d`, and up to three repeated `tank_id` values.
  Custom requests require ISO `start` and `end` values, are limited to 30 days,
  and all requests are capped at 1,000 buckets. The response contains complete
  nullable timelines, fleet and selected-tank series, previous-period
  statistics, alert events, effective threshold segments, and classified
  reporting uptime.
- A future WebSocket path may be added; the current
  `backend/app/websockets/sensor_stream.py` is only a placeholder.

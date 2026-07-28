# AquaLogic API Contract

Status: Current route inventory
Last reviewed: 2026-07-29

The running FastAPI application at `backend/app/main.py` is the executable
contract. This document is a navigation aid; response models and tests remain
the final authority for exact fields and validation.

## Authentication

Authenticated routes use the 15-minute bearer token returned by `POST /auth/login`
or `POST /auth/refresh`. The browser keeps this token in memory; the seven-day
opaque refresh token is an HttpOnly, SameSite=Strict cookie. All access tokens
carry session and token-version claims, so legacy tokens intentionally fail.

| Method | Route | Access | Purpose |
| --- | --- | --- | --- |
| POST | `/auth/login` | Public | Authenticate an active user |
| POST | `/auth/logout` | Authenticated | Client-side JWT logout acknowledgement |
| POST | `/auth/refresh` | Refresh cookie | Rotate the refresh token and return a new access token |
| POST | `/auth/logout-all` | Authenticated | Verify current password and revoke every session |
| GET | `/auth/me` | Authenticated | Read current user |
| POST | `/auth/change-password` | Authenticated | Complete or change password |
| POST | `/auth/setup-password` | Setup link | Atomically activate or reset an account from a one-time token |
| GET/DELETE | `/auth/sessions` and `/auth/sessions/{session_id}` | Authenticated | List/revoke the caller's sessions |

User creation and reset responses return one-time `setup_url` values rather
than plaintext passwords. Setup links are fragment tokens and expire after 30
minutes. Password changes and resets revoke existing sessions.

## Core staff resources

| Method | Route | Purpose |
| --- | --- | --- |
| GET/POST | `/tanks` | Staff list; admin creates |
| GET/PUT/DELETE | `/tanks/{tank_id}` | Staff reads; admin updates or deletes |
| GET | `/tanks/{tank_id}/species-suitability` | Derive staff-only species-care suitability from the latest reading |
| POST/DELETE | `/tanks/{tank_id}/fish` and `/tanks/{tank_id}/fish/{fish_id}` | Manage tank/species assignments |
| GET/POST | `/fish` | Staff lists; admin creates |
| GET/PUT/DELETE | `/fish/{fish_id}` | Staff reads; admin updates or deletes |
| GET | `/tanks/{tank_id}/sensors` | Read latest sensor data |
| GET | `/tanks/{tank_id}/sensors/history` | Read bounded sensor history |
| POST | `/tanks/{tank_id}/sensors` | Admin-only manual sensor submission |
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
| GET/POST | `/customers` | Staff reads; admin creates |
| PUT/DELETE | `/customers/{customer_id}` | Admin | Update or delete customers |
| GET | `/users` | Admin | List staff users |
| PUT | `/users/{user_id}` | Admin | Update role or active state |
| POST | `/users` | Admin | Create a user and return a one-time setup URL |
| POST | `/users/{user_id}/reset-password` | Admin | Disable the password/sessions and issue a setup URL |
| GET | `/security/audit-events` | Admin | Read up to 100 newest security audit events before an optional ID |

## Public route

| Method | Route | Access | Purpose |
| --- | --- | --- | --- |
| GET | `/public/tanks/{public_id}` | Public | Read a public QR tank view |

The public route only returns tanks marked public and uses the public identifier.
The web route consuming it is `/tank/:publicId`.

It exposes only `display_location`, not the internal location; excludes tank
code and feeding schedule; rounds readings; and rounds observation timestamps to
the minute. Public image URLs require HTTPS and a configured host allowlist.

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
- `GET /tanks/{tank_id}/species-suitability` returns derived `suitable`,
  `attention`, or `unavailable` results for assigned species. It evaluates
  temperature, pH, dissolved oxygen, and TDS against fish preferred ranges and
  the latest reading only; it does not create alerts or use operational
  thresholds. The response includes per-parameter reasons, range values, a
  reading freshness reference, and `no_species_assigned` for empty tanks.
  Preferred temperature, pH, and TDS minimums cannot exceed their maximums on
  fish create or update requests.
- `GET /tanks/{tank_id}/operations` returns one internally consistent, UTC
  evaluated operational snapshot: latest reading (or `null`), six
  threshold-backed parameter statuses, and unresolved persisted alerts newest
  first. A missing reading is `offline` with `unavailable` parameters; a stale
  reading is `offline` with `offline` parameters.
- `GET /tanks/{tank_id}` adds the optional minimal `customer` summary while
  retaining `customer_id` and assigned `fish_species`. `GET /fleet` adds the
  lightweight derived `species_care_status` and `assigned_species_count`; it
  does not expose per-species checks.
- `GET /analytics/fleet` accepts `range=24h|7d|30d|custom`,
  `bucket=auto|15m|1h|6h|1d`, and up to three repeated `tank_id` values.
  Custom requests require ISO `start` and `end` values, are limited to 30 days,
  and all requests are capped at 1,000 buckets. The response contains complete
  nullable timelines, fleet and selected-tank series, previous-period
  statistics, alert events, effective threshold segments, and classified
  reporting uptime.
- A future WebSocket path may be added; the current
  `backend/app/websockets/sensor_stream.py` is only a placeholder.

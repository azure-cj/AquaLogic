# AquaLogic Backend

FastAPI backend for AquaLogic. The backend is the shared source of operational
data for the web application and future connected mobile and hardware clients.

## Current capabilities

- FastAPI app scaffold
- SQLAlchemy models for users, tanks, fish species, assignments, sensor readings, and alerts
- JWT-based staff authentication
- CRUD endpoints for tanks and fish species
- Tank-fish assignment endpoints
- Sensor reading persistence endpoints
- Threshold-backed status evaluation and rule-based alert generation
- Alert listing, filtering, history, and resolution
- Public tank read-only endpoint for QR pages
- Fleet dashboard, management, threshold, and analytics endpoints
- Alembic migration history through the current migrations
- Seed scripts for sample tanks and fish species
- Optional demo sensor generator behind explicit environment flags
- Pytest API and behavior tests

## Quick start

1. Create a virtual environment and install dependencies:

   ```bash
   python -m venv .venv
   .venv\Scripts\activate
   pip install -r requirements.txt
   ```

2. Create environment file:

   ```bash
   copy .env.example .env
   ```

3. Run database migrations:

   ```bash
   alembic upgrade head
   ```

4. Seed sample data:

   ```bash
   python -m seed.seed_data
   ```

5. Start the API:

   ```bash
   uvicorn app.main:app --reload
   ```

6. Open docs:

   - Swagger UI: http://127.0.0.1:8000/docs
   - ReDoc: http://127.0.0.1:8000/redoc

## Tests

```bash
pytest -q
```

## Notes

- Login endpoint: `POST /auth/login`
- Public tank endpoint: `GET /public/tanks/{public_id}`
- Local development defaults to SQLite. Production requires explicit CORS
  origins and deployment database configuration.
- The mobile app is currently a local demo-data prototype and does not yet use
  this API.
- WebSocket streaming remains a future extension; the current module is a
  placeholder.

For broader repository context, read `../AGENTS.md`, `../docs/INDEX.md`, and
`../docs/areas/BACKEND.md`.

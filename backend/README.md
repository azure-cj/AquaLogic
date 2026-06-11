# AquaLogic Backend (Phase 1)

FastAPI backend foundation for AquaLogic.

## Included in this phase

- FastAPI app scaffold
- SQLAlchemy models for users, tanks, fish species, assignments, sensor readings, and alerts
- JWT-based staff authentication
- CRUD endpoints for tanks and fish species
- Tank-fish assignment endpoints
- Sensor reading persistence endpoints
- Alert listing and resolve endpoints
- Public tank read-only endpoint for QR pages
- Alembic migration setup with initial migration
- Seed scripts for sample tanks and fish species
- Pytest API tests

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
- Public tank endpoint: `GET /public/tanks/{id}`
- This phase intentionally excludes decision engine logic, mock sensor generator runtime loop, and WebSocket streaming implementation.

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import settings
from .database import Base, engine
from .routes import alerts, auth, dashboard, fish, management, public, sensors, species_suitability, tanks
from .services.decision_engine import ensure_default_thresholds
from .services.demo_sensor import start_demo_generator

# Ensure all SQLAlchemy models are registered before metadata is used.
from . import models  # noqa: F401

app = FastAPI(title=settings.app_name)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def on_startup() -> None:
    # Production schema ownership belongs to Alembic. This local convenience is opt-in only.
    if settings.environment != "production":
        Base.metadata.create_all(bind=engine)
        from .database import SessionLocal
        db = SessionLocal()
        try: ensure_default_thresholds(db)
        finally: db.close()
    start_demo_generator()


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


app.include_router(auth.router)
app.include_router(tanks.router)
app.include_router(species_suitability.router)
app.include_router(fish.router)
app.include_router(sensors.router)
app.include_router(alerts.router)
app.include_router(public.router)
app.include_router(management.router)
app.include_router(dashboard.router)

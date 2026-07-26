"""Optional single-instance synthetic data loop for demo deployments."""
import threading
import time
from sqlalchemy import select
from app.config import settings
from app.database import SessionLocal
from app.models import Tank
from app.services.decision_engine import ingest_reading


def _loop() -> None:
    cycle = 0
    while True:
        with SessionLocal() as db:
            tanks = list(db.scalars(select(Tank).order_by(Tank.id)).all())
            for index, tank in enumerate(tanks):
                # Sustained, deterministic patterns expose normal, warning, and critical states.
                ammonia = 0.1 if index % 3 == 0 else (0.35 if index % 3 == 1 else 0.7)
                ingest_reading(db, tank.id, {"temperature": 25.5 + (cycle % 2) * .1, "ph": 7.1, "turbidity": 3, "dissolved_oxygen": 6.2, "tds": 180, "ammonia": ammonia, "is_mock": True})
        cycle += 1
        time.sleep(settings.demo_sensor_interval_seconds)


def start_demo_generator() -> None:
    # Render and local development can run multiple API workers.  The explicit
    # instance flag makes exactly one designated process responsible for demo
    # ingestion, while every other process remains a normal API worker.
    if settings.demo_sensor_enabled and settings.demo_sensor_instance:
        threading.Thread(target=_loop, name="aqualogic-demo-sensors", daemon=True).start()

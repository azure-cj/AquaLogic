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
            for tank in tanks:
                # Keep one service tank deliberately stale while the other demo
                # habitats report deterministic normal, warning, and critical states.
                if tank.tank_code == "SERVICE-01":
                    continue
                ammonia = 0.1
                if tank.tank_code == "DISPLAY-02":
                    ammonia = 0.35
                elif tank.tank_code == "BREED-01":
                    ammonia = 0.7
                ingest_reading(db, tank.id, {"temperature": 25.5 + (cycle % 2) * .1, "ph": 7.1, "turbidity": 3, "dissolved_oxygen": 6.2, "tds": 180, "ammonia": ammonia, "is_mock": True})
        cycle += 1
        time.sleep(settings.demo_sensor_interval_seconds)


def start_demo_generator() -> None:
    # Render and local development can run multiple API workers.  The explicit
    # instance flag makes exactly one designated process responsible for demo
    # ingestion, while every other process remains a normal API worker.
    if settings.demo_sensor_enabled and settings.demo_sensor_instance:
        threading.Thread(target=_loop, name="aqualogic-demo-sensors", daemon=True).start()

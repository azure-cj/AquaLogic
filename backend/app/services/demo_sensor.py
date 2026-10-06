"""Optional single-instance synthetic data loop for demo deployments."""
import threading
import time
from datetime import datetime, timezone
from fastapi import HTTPException
from sqlalchemy import select
from app.config import settings
from app.database import SessionLocal
from app.models import RegisteredDevice, Tank
from app.services.decision_engine import ingest_reading
from app.services.tank_lifecycle import lock_tank_for_mutation
from seed.demo_scenarios import SCENARIOS, PARAMETERS, scenario_value


def write_demo_cycle(db, *, now=None):
    """Write mapped active demo tanks only; never fill a real device's tank."""
    now = now or datetime.now(timezone.utc)
    active_device = select(RegisteredDevice.id).where(
        RegisteredDevice.tank_id == Tank.id, RegisteredDevice.is_active.is_(True)).exists()
    ids = list(db.scalars(select(Tank.id).where(Tank.tank_code.in_(SCENARIOS),
                Tank.retired_at.is_(None), ~active_device).order_by(Tank.id)))
    written = 0
    for tank_id in ids:
        try:
            tank = lock_tank_for_mutation(db, tank_id)
        except HTTPException as exc:
            db.rollback()
            if exc.status_code == 404:
                continue  # Removed since the candidate query.
            raise
        db.refresh(tank)
        if tank.retired_at is not None or tank.tank_code not in SCENARIOS or SCENARIOS[tank.tank_code] == 'offline':
            db.rollback()
            continue
        # Share the existing lifecycle lock with device provisioning/retirement;
        # the active-device check and write cannot race those operations.
        if db.scalar(select(RegisteredDevice.id).where(
                RegisteredDevice.tank_id == tank.id, RegisteredDevice.is_active.is_(True)).limit(1)):
            db.rollback()
            continue
        ingest_reading(db, tank.id, {**{parameter: scenario_value(tank.tank_code, parameter, now)
                                      for parameter in PARAMETERS},
                                   'timestamp': now, 'is_mock': True}, received_at=now)
        written += 1
    return written


def _loop() -> None:
    while True:
        with SessionLocal() as db:
            write_demo_cycle(db)
        time.sleep(settings.demo_sensor_interval_seconds)


def start_demo_generator() -> None:
    # Render and local development can run multiple API workers.  The explicit
    # instance flag makes exactly one designated process responsible for demo
    # ingestion, while every other process remains a normal API worker.
    if settings.demo_sensor_enabled and settings.demo_sensor_instance:
        threading.Thread(target=_loop, name="aqualogic-demo-sensors", daemon=True).start()

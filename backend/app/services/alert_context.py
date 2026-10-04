"""Derived alert investigation context without additional persistence."""
from dataclasses import asdict
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import SensorReading, Tank
from app.schemas.alert import AlertRead
from app.schemas.sensor import make_timestamp_explicit_utc
from app.services.operator_guidance import guidance_for
from app.services.reading_freshness import is_reading_current
from app.services.thresholds import resolve_effective_thresholds
from app.services.alert_species_context import build_species_context

UNITS = {"temperature": "°C", "ph": "pH", "turbidity": "NTU", "tds": "ppm"}


def build_alert_context(db: Session, alert, *, evaluated_at=None) -> dict:
    now = evaluated_at or datetime.now(timezone.utc)
    tank = db.get(Tank, alert.tank_id)
    linked = db.get(SensorReading, alert.reading_id) if alert.reading_id else None
    # Never expose a reading associated with another tank, including legacy data.
    if linked is not None and linked.tank_id != alert.tank_id:
        linked = None
    latest = db.scalar(select(SensorReading).where(SensorReading.tank_id == alert.tank_id)
                       .order_by(SensorReading.received_at.desc(), SensorReading.id.desc()).limit(1))
    historical = (resolve_effective_thresholds(db, alert.tank_id, as_of=linked.received_at).get(alert.parameter)
                  if linked is not None else None)
    current = resolve_effective_thresholds(db, alert.tank_id).get(alert.parameter)

    def reading_context(reading):
        if reading is None:
            return None
        return {
            "reading_id": reading.id, "value": getattr(reading, alert.parameter, None),
            "unit": UNITS.get(alert.parameter, current.unit if current else ""),
            "observed_at": make_timestamp_explicit_utc(reading.timestamp),
            "received_at": make_timestamp_explicit_utc(reading.received_at),
            "reporting_freshness": "fresh" if is_reading_current(reading.timestamp, received_at=reading.received_at, evaluated_at=now) else "stale",
        }

    return {
        "alert": AlertRead.model_validate(alert),
        "tank": {"id": tank.id, "display_name": tank.name, "lifecycle": tank.lifecycle},
        "evaluated_at": now,
        "linked_reading": reading_context(linked),
        "linked_threshold": asdict(historical) if historical else None,
        "latest_reading": reading_context(latest),
        "current_threshold": asdict(current) if current else None,
        "guidance": guidance_for(alert.parameter, getattr(linked, alert.parameter, None), historical),
        "species_context": build_species_context(tank, alert.parameter, latest, now),
    }

"""Deterministic dashboard history for local demonstrations."""
from datetime import datetime, timedelta, timezone
from math import sin

from sqlalchemy import insert, select
from sqlalchemy.orm import Session

from app.models import Alert, AlertSeverity, FishSpecies, SensorReading, Tank, TankFish

DEMO_HISTORY_DAYS = 7
DEMO_INTERVAL_SECONDS = 30

LATEST_STATES = {
    "Riverbank Community": "normal",
    "Guppy Gallery": "warning",
    "Breeder Bay": "critical",
    "Juvenile Grove": "normal",
    "Recovery Reef": "offline",
    "Calmwater Rack": "normal",
    "Observation Point": "normal",
}

FISH_ASSIGNMENTS = {
    "Riverbank Community": ("Neon Tetra", "Corydoras Catfish", "Angelfish"),
    "Guppy Gallery": ("Guppy", "Platy", "Molly"),
    "Breeder Bay": ("Guppy", "Platy"),
    "Juvenile Grove": ("Guppy", "Molly"),
    "Recovery Reef": ("Betta",),
    "Calmwater Rack": ("Discus", "Corydoras Catfish"),
    "Observation Point": ("Angelfish", "Neon Tetra"),
}


def _rounded_now() -> datetime:
    now = datetime.now(timezone.utc).replace(microsecond=0)
    return now - timedelta(seconds=now.second % DEMO_INTERVAL_SECONDS)


def _reading_values(tank_index: int, sample_index: int) -> dict[str, float]:
    wave = sin((sample_index + tank_index * 47) / 120)
    slower_wave = sin((sample_index + tank_index * 83) / 420)
    return {
        "temperature": round(25.4 + wave * 0.35 + tank_index * 0.025, 2),
        "ph": round(7.1 + slower_wave * 0.08 - wave * 0.025, 2),
        "turbidity": round(2.8 + abs(wave) * 0.8, 2),
        "dissolved_oxygen": round(6.3 - abs(wave) * 0.2 - slower_wave * 0.08, 2),
        "tds": round(180 + wave * 8, 2),
        "ammonia": round(0.08 + abs(wave) * 0.03 + max(0, slower_wave) * 0.01, 2),
    }


def _alert_message(parameter: str, severity: AlertSeverity) -> str:
    return f"{parameter.replace('_', ' ').title()} is outside its {severity.value} threshold"


def _assign_demo_fish(db: Session, tanks: list[Tank]) -> int:
    fish_by_name = {fish.common_name: fish for fish in db.scalars(select(FishSpecies)).all()}
    created = 0
    for tank in tanks:
        for fish_name in FISH_ASSIGNMENTS.get(tank.name, ()):
            fish = fish_by_name.get(fish_name)
            if fish is None:
                continue
            exists = db.scalar(
                select(TankFish).where(
                    TankFish.tank_id == tank.id,
                    TankFish.fish_species_id == fish.id,
                )
            )
            if exists is None:
                db.add(TankFish(tank_id=tank.id, fish_species_id=fish.id))
                created += 1
    return created


def seed_dashboard_demo(
    db: Session,
    history_days: int = DEMO_HISTORY_DAYS,
    interval_seconds: int = DEMO_INTERVAL_SECONDS,
) -> dict[str, int]:
    """Seed missing local demo history without replacing real readings or alerts."""
    if history_days < 1 or interval_seconds < 1:
        raise ValueError("history_days and interval_seconds must be positive")

    tanks = list(db.scalars(select(Tank).order_by(Tank.tank_code)).all())
    fish_assignments = _assign_demo_fish(db, tanks)
    now = _rounded_now()
    start = now - timedelta(days=history_days)
    samples_per_day = 86_400 // interval_seconds
    total_steps = history_days * samples_per_day
    offline_steps = max(1, 600 // interval_seconds)
    historical_events = (
        ("Riverbank Community", samples_per_day * 2, "dissolved_oxygen", AlertSeverity.warning, 4.4),
        ("Juvenile Grove", samples_per_day * 4, "turbidity", AlertSeverity.warning, 10.2),
        ("Calmwater Rack", samples_per_day * 5, "ph", AlertSeverity.warning, 8.1),
    )
    event_values = {
        (tank_name, sample_index): (parameter, value)
        for tank_name, sample_index, parameter, _severity, value in historical_events
    }
    event_radius = 300 // interval_seconds
    reporting_gaps = {
        # A recent two-hour gap demonstrates a critical reporting state while
        # retaining a current reading after recovery.
        "Observation Point": ((total_steps - 480, total_steps - 240),),
        # Two shorter gaps make contiguous-gap counting and degraded uptime visible.
        "Guppy Gallery": (
            (total_steps - 1_440, total_steps - 1_400),
            (total_steps - 760, total_steps - 720),
        ),
    }
    seeded_tanks: list[Tank] = []
    readings_created = 0

    for tank_index, tank in enumerate(tanks):
        if db.scalar(select(SensorReading.id).where(SensorReading.tank_id == tank.id).limit(1)):
            continue

        last_step = total_steps
        if LATEST_STATES.get(tank.name) == "offline":
            last_step -= offline_steps

        batch: list[dict] = []
        for sample_index in range(last_step + 1):
            if any(
                gap_start <= sample_index <= gap_end
                for gap_start, gap_end in reporting_gaps.get(tank.name, ())
            ):
                continue
            values = _reading_values(tank_index, sample_index)
            event = next(
                (
                    event_values[(event_tank, event_index)]
                    for event_tank, event_index in event_values
                    if event_tank == tank.name
                    and abs(event_index - sample_index) <= event_radius
                ),
                None,
            )
            if event:
                values[event[0]] = event[1]
            if sample_index == last_step:
                state = LATEST_STATES.get(tank.name)
                if state == "warning":
                    values["ammonia"] = 0.35
                elif state == "critical":
                    values["ammonia"] = 0.7
            timestamp = start + timedelta(seconds=sample_index * interval_seconds)
            batch.append({
                "tank_id": tank.id,
                "timestamp": timestamp,
                "received_at": timestamp,
                **values,
                "is_mock": True,
            })
            if len(batch) == 5_000:
                db.execute(insert(SensorReading), batch)
                readings_created += len(batch)
                batch.clear()
        if batch:
            db.execute(insert(SensorReading), batch)
            readings_created += len(batch)
        seeded_tanks.append(tank)
    db.flush()

    alerts_created = 0
    tanks_by_name = {tank.name: tank for tank in seeded_tanks}
    for tank_name, sample_index, parameter, severity, _value in historical_events:
        tank = tanks_by_name.get(tank_name)
        if tank is None:
            continue
        timestamp = start + timedelta(seconds=sample_index * interval_seconds)
        reading = db.scalar(
            select(SensorReading).where(
                SensorReading.tank_id == tank.id,
                SensorReading.timestamp == timestamp,
            )
        )
        if reading is None:
            continue
        if db.scalar(select(Alert.id).where(Alert.reading_id == reading.id, Alert.parameter == parameter)):
            continue
        db.add(Alert(
            tank_id=tank.id,
            reading_id=reading.id,
            parameter=parameter,
            severity=severity,
            message=_alert_message(parameter, severity),
            is_resolved=True,
            created_at=timestamp,
            resolved_at=timestamp + timedelta(minutes=20),
        ))
        alerts_created += 1

    for tank_name, severity, ammonia in (
        ("Guppy Gallery", AlertSeverity.warning, 0.35),
        ("Breeder Bay", AlertSeverity.critical, 0.7),
    ):
        tank = tanks_by_name.get(tank_name)
        if tank is None:
            continue
        reading = db.scalar(
            select(SensorReading)
            .where(SensorReading.tank_id == tank.id)
            .order_by(SensorReading.timestamp.desc())
            .limit(1)
        )
        if reading is None or db.scalar(
            select(Alert.id).where(Alert.reading_id == reading.id, Alert.parameter == "ammonia")
        ):
            continue
        db.add(Alert(
            tank_id=tank.id,
            reading_id=reading.id,
            parameter="ammonia",
            severity=severity,
            message=_alert_message("ammonia", severity),
            is_resolved=False,
            created_at=now - timedelta(minutes=15),
        ))
        alerts_created += 1

    db.commit()
    return {
        "fish_assignments": fish_assignments,
        "readings": readings_created,
        "alerts": alerts_created,
    }

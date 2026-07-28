from sqlalchemy import func, select

from app.models import Alert, SensorReading, Tank
from app.services.decision_engine import ensure_default_thresholds, status_for_reading
from seed.seed_dashboard_demo import seed_dashboard_demo
from seed.seed_fish import seed_fish_species
from seed.seed_tanks import seed_tanks


def test_dashboard_demo_seed_creates_idempotent_history_alerts_and_public_details(db_session):
    seed_tanks(db_session)
    seed_fish_species(db_session)
    ensure_default_thresholds(db_session)

    first = seed_dashboard_demo(db_session, history_days=7, interval_seconds=43_200)
    assert first["readings"] == 104
    assert first["alerts"] == 5
    assert first["fish_assignments"] > 0

    tanks = list(db_session.scalars(select(Tank).order_by(Tank.name)).all())
    assert all(tank.feeding_schedule and tank.public_care_notes and tank.hero_image_url for tank in tanks)

    statuses = {}
    for tank in tanks:
        latest = db_session.scalar(
            select(SensorReading)
            .where(SensorReading.tank_id == tank.id)
            .order_by(SensorReading.timestamp.desc())
            .limit(1)
        )
        statuses[tank.name] = status_for_reading(db_session, latest)
    assert statuses["Riverbank Community"] == "normal"
    assert statuses["Guppy Gallery"] == "warning"
    assert statuses["Breeder Bay"] == "critical"
    assert statuses["Recovery Reef"] == "offline"
    assert db_session.scalar(select(func.count(Alert.id)).where(Alert.is_resolved.is_(False))) == 2
    assert db_session.scalar(select(func.count(Alert.id)).where(Alert.is_resolved.is_(True))) == 3

    second = seed_dashboard_demo(db_session, history_days=7, interval_seconds=43_200)
    assert second["readings"] == 0
    assert second["alerts"] == 0
    assert db_session.scalar(select(func.count(SensorReading.id))) == 104

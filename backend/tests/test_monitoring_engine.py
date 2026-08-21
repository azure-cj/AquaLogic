from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

from sqlalchemy import select

from app.models import Alert, SecurityAuditEvent, SensorReading, Tank, ThresholdConfig
from app.services.decision_engine import (
    ensure_default_thresholds,
    ingest_reading,
    parameter_statuses,
    status_for_reading,
)
from app.services.reading_freshness import is_reading_current


def _tank(db_session, name="Monitoring tank"):
    tank = Tank(name=name, location="Monitoring rack")
    db_session.add(tank)
    db_session.commit()
    db_session.refresh(tank)
    return tank


def _values(temperature=25.0, *, ph=7.0, turbidity=2.0, tds=150.0):
    return {
        "temperature": temperature,
        "ph": ph,
        "turbidity": turbidity,
        "dissolved_oxygen": None,
        "tds": tds,
        "ammonia": None,
        "is_mock": True,
    }


def test_threshold_bounds_are_strict_and_one_sided_bounds_remain_valid(client, auth_headers, db_session):
    ensure_default_thresholds(db_session)

    equal_bounds = client.put(
        "/thresholds/temperature",
        headers=auth_headers,
        json={
            "unit": "°C",
            "critical_min": 18,
            "warning_min": 20,
            "warning_max": 28,
            "critical_max": 28,
            "enabled": True,
        },
    )
    assert equal_bounds.status_code == 422

    one_sided = client.put(
        "/thresholds/turbidity",
        headers=auth_headers,
        json={
            "unit": "NTU",
            "critical_min": None,
            "warning_min": None,
            "warning_max": 8,
            "critical_max": 15,
            "enabled": True,
        },
    )
    assert one_sided.status_code == 200


def test_exact_threshold_edges_remain_normal(db_session):
    ensure_default_thresholds(db_session)
    tank = _tank(db_session, "Threshold edges")

    for temperature in (18.0, 20.0, 28.0, 30.0):
        reading = ingest_reading(db_session, tank.id, _values(temperature))
        assert status_for_reading(db_session, reading) == "normal"


def test_partial_and_unusable_readings_have_explicit_statuses(db_session):
    ensure_default_thresholds(db_session)
    now = datetime.now(timezone.utc)
    partial = SimpleNamespace(
        timestamp=now,
        received_at=now,
        temperature=25.0,
        ph=None,
        turbidity=None,
        dissolved_oxygen=None,
        tds=None,
        ammonia=None,
    )
    assert status_for_reading(db_session, partial, evaluated_at=now) == "normal"
    statuses = parameter_statuses(db_session, partial, evaluated_at=now)
    assert statuses["temperature"] == "normal"
    assert statuses["ph"] == "unavailable"

    unusable = SimpleNamespace(
        timestamp=now,
        received_at=now,
        temperature=None,
        ph=None,
        turbidity=None,
        dissolved_oxygen=None,
        tds=None,
        ammonia=None,
    )
    assert status_for_reading(db_session, unusable, evaluated_at=now) == "offline"


def test_disabled_threshold_is_unavailable_and_resolves_on_next_reading(db_session):
    ensure_default_thresholds(db_session)
    tank = _tank(db_session, "Disabled threshold")
    critical = ingest_reading(db_session, tank.id, _values(31.0))
    alert = db_session.scalar(
        select(Alert).where(Alert.tank_id == tank.id, Alert.parameter == "temperature")
    )
    assert alert is not None
    assert alert.is_resolved is False

    threshold = db_session.scalar(
        select(ThresholdConfig).where(ThresholdConfig.parameter == "temperature")
    )
    assert threshold is not None
    threshold.enabled = False
    db_session.commit()

    next_reading = ingest_reading(db_session, tank.id, _values(25.0))
    db_session.refresh(alert)
    assert alert.is_resolved is True
    assert alert.resolution_source == "system"
    assert alert.resolved_at == next_reading.received_at
    event = db_session.scalar(
        select(SecurityAuditEvent)
        .where(SecurityAuditEvent.event_type == "alert.auto_resolve")
        .order_by(SecurityAuditEvent.id.desc())
    )
    assert event is not None
    assert '"reason":"threshold_disabled"' in (event.details or "")
    assert parameter_statuses(db_session, next_reading)["temperature"] == "unavailable"


def test_threshold_changes_are_prospective_and_preserve_existing_alert(db_session):
    ensure_default_thresholds(db_session)
    tank = _tank(db_session, "Prospective threshold")
    ingest_reading(db_session, tank.id, _values(31.0))
    alert = db_session.scalar(
        select(Alert).where(Alert.tank_id == tank.id, Alert.parameter == "temperature")
    )
    assert alert is not None and alert.is_resolved is False

    threshold = db_session.scalar(
        select(ThresholdConfig).where(ThresholdConfig.parameter == "temperature")
    )
    assert threshold is not None
    threshold.warning_max = 35
    threshold.critical_max = 40
    db_session.commit()
    db_session.refresh(alert)
    assert alert.is_resolved is False

    ingest_reading(db_session, tank.id, _values(31.0))
    db_session.refresh(alert)
    assert alert.is_resolved is True
    assert alert.resolution_source == "system"


def test_alert_lifecycle_escalates_downgrades_resolves_and_creates_new_incident(db_session):
    ensure_default_thresholds(db_session)
    tank = _tank(db_session, "Alert lifecycle")

    ingest_reading(db_session, tank.id, _values(31.0))
    alert = db_session.scalar(
        select(Alert).where(Alert.tank_id == tank.id, Alert.parameter == "temperature")
    )
    assert alert is not None
    assert alert.severity.value == "critical"

    ingest_reading(db_session, tank.id, _values(29.0))
    db_session.refresh(alert)
    assert alert.severity.value == "warning"
    assert alert.is_resolved is False

    normal = ingest_reading(db_session, tank.id, _values(25.0))
    db_session.refresh(alert)
    assert alert.is_resolved is True
    assert alert.resolution_source == "system"
    assert alert.resolved_at == normal.received_at

    ingest_reading(db_session, tank.id, _values(31.0))
    alerts = list(
        db_session.scalars(
            select(Alert)
            .where(Alert.tank_id == tank.id, Alert.parameter == "temperature")
            .order_by(Alert.id)
        ).all()
    )
    assert len(alerts) == 2
    assert alerts[0].is_resolved is True
    assert alerts[1].is_resolved is False
    assert alerts[1].id != alerts[0].id


def test_manual_resolution_records_operator_source(client, auth_headers, db_session):
    ensure_default_thresholds(db_session)
    tank = _tank(db_session, "Manual resolution")
    ingest_reading(db_session, tank.id, _values(31.0))
    alert = db_session.scalar(
        select(Alert).where(Alert.tank_id == tank.id, Alert.parameter == "temperature")
    )
    assert alert is not None

    response = client.put(f"/alerts/{alert.id}/resolve", headers=auth_headers)
    assert response.status_code == 200
    assert response.json()["resolution_source"] == "operator"
    db_session.refresh(alert)
    assert alert.resolution_source == "operator"


def test_freshness_uses_receipt_time_and_accepts_late_observation(db_session):
    now = datetime.now(timezone.utc)
    assert is_reading_current(now - timedelta(seconds=90), evaluated_at=now)
    assert not is_reading_current(now - timedelta(seconds=90, milliseconds=1), evaluated_at=now)

    ensure_default_thresholds(db_session)
    tank = _tank(db_session, "Late observations")
    older_observation = now - timedelta(hours=2)
    reading = ingest_reading(
        db_session,
        tank.id,
        {**_values(), "timestamp": older_observation},
    )
    assert reading.timestamp.replace(tzinfo=timezone.utc) == older_observation
    assert status_for_reading(db_session, reading, evaluated_at=now) == "normal"

    later_receipt = reading.received_at + timedelta(seconds=1)
    newer = SensorReading(
        tank_id=tank.id,
        timestamp=older_observation - timedelta(minutes=1),
        received_at=later_receipt,
        temperature=25,
        ph=7,
        turbidity=2,
        dissolved_oxygen=None,
        tds=150,
        ammonia=None,
    )
    db_session.add(newer)
    db_session.commit()
    selected = db_session.scalar(
        select(SensorReading)
        .where(SensorReading.tank_id == tank.id)
        .order_by(SensorReading.received_at.desc(), SensorReading.id.desc())
        .limit(1)
    )
    assert selected is not None
    assert selected.id == newer.id

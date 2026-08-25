from datetime import datetime, timedelta, timezone
from pathlib import Path
import threading
from threading import Barrier, Thread

import pytest
from sqlalchemy import create_engine, func, select
from sqlalchemy.orm import sessionmaker

from app.config import _validate_monitoring, settings
from app.database import Base, configure_sqlite_foreign_keys
from app.models import Alert, MonitoringIncident, RegisteredDevice, SecurityAuditEvent, SensorReading, Tank
from app.security import hash_opaque_token
from app.services.decision_engine import ensure_default_thresholds, ingest_reading
from app.services import monitoring_incidents
from app.services.monitoring_incidents import detect_monitoring_incidents


def _values(temperature=25.0):
    return {
        "temperature": temperature,
        "ph": 7.0,
        "turbidity": 2.0,
        "dissolved_oxygen": None,
        "tds": 150.0,
        "ammonia": None,
        "is_mock": False,
    }


def _tank(client, headers, name="Incident tank"):
    response = client.post("/tanks", headers=headers, json={"name": name, "location": "Rack"})
    assert response.status_code == 201
    return response.json()


def _register(client, headers, tank_id, device_id="incident-device"):
    response = client.post(
        "/devices",
        headers=headers,
        json={"tank_id": tank_id, "device_id": device_id},
    )
    assert response.status_code == 201
    return response.json()


def _make_overdue(db_session, tank_id: int, now: datetime, *, seconds: int = 900) -> None:
    tank = db_session.get(Tank, tank_id)
    assert tank is not None
    tank.monitoring_expected_at = now - timedelta(seconds=seconds)
    db_session.commit()


def test_grace_defaults_above_offline_boundary_and_rejects_unsafe_values():
    assert settings.monitoring_outage_grace_seconds == 900
    assert settings.monitoring_outage_grace_seconds > 90
    with pytest.raises(ValueError, match="strictly greater"):
        _validate_monitoring(settings.__class__(**{
            **settings.__dict__,
            "monitoring_outage_grace_seconds": 90,
        }))


def test_periodic_maintenance_stops_cleanly(monkeypatch):
    completed = threading.Event()
    calls = []

    def fake_maintenance(*, evaluated_at=None):
        calls.append(evaluated_at)
        completed.set()
        return monitoring_incidents.MaintenanceResult(actuator_unknown_transitions=0, monitoring=None)

    monkeypatch.setattr(monitoring_incidents, "run_periodic_maintenance", fake_maintenance)
    handle = monitoring_incidents.start_periodic_maintenance()
    try:
        assert completed.wait(timeout=2)
        assert calls
    finally:
        handle.stop()
    assert not handle.thread.is_alive()


def test_detector_respects_grace_creates_one_incident_and_restart_is_idempotent(
    client, auth_headers, db_session
):
    tank = _tank(client, auth_headers)
    _register(client, auth_headers, tank["id"])
    now = datetime(2026, 8, 22, 12, 0, tzinfo=timezone.utc)

    _make_overdue(db_session, tank["id"], now, seconds=899)
    before_grace = detect_monitoring_incidents(db_session, evaluated_at=now, grace_seconds=900)
    assert before_grace.created_incidents == 0

    _make_overdue(db_session, tank["id"], now, seconds=900)
    opened = detect_monitoring_incidents(db_session, evaluated_at=now, grace_seconds=900)
    assert opened.created_incidents == 1
    restarted = detect_monitoring_incidents(db_session, evaluated_at=now + timedelta(minutes=1), grace_seconds=900)
    assert restarted.created_incidents == 0
    incidents = list(db_session.scalars(select(MonitoringIncident)).all())
    assert len(incidents) == 1
    assert incidents[0].resolved_at is None


def test_detector_skips_tanks_without_active_devices(client, auth_headers, db_session):
    tank = _tank(client, auth_headers, "No device incident tank")
    now = datetime(2026, 8, 22, 12, 0, tzinfo=timezone.utc)
    _make_overdue(db_session, tank["id"], now, seconds=900)
    result = detect_monitoring_incidents(db_session, evaluated_at=now, grace_seconds=900)
    assert result.eligible_tanks == 0
    assert db_session.scalar(select(MonitoringIncident.id)) is None


def test_first_device_and_reactivation_each_receive_a_full_grace_period(
    client, auth_headers, db_session
):
    tank = _tank(client, auth_headers, "Expectation boundary tank")
    before_device = datetime(2026, 8, 22, 12, 0, tzinfo=timezone.utc)
    assert detect_monitoring_incidents(
        db_session, evaluated_at=before_device + timedelta(hours=1), grace_seconds=900
    ).created_incidents == 0

    _register(client, auth_headers, tank["id"], "expectation-device")
    db_session.expire_all()
    expected_at = db_session.get(Tank, tank["id"]).monitoring_expected_at
    assert expected_at is not None
    expected_at = expected_at.replace(tzinfo=timezone.utc) if expected_at.tzinfo is None else expected_at
    assert detect_monitoring_incidents(
        db_session, evaluated_at=expected_at + timedelta(seconds=899), grace_seconds=900
    ).created_incidents == 0
    assert detect_monitoring_incidents(
        db_session, evaluated_at=expected_at + timedelta(seconds=900), grace_seconds=900
    ).created_incidents == 1

    assert client.patch(
        "/devices/expectation-device",
        headers=auth_headers,
        json={"is_active": False},
    ).status_code == 200
    assert client.patch(
        "/devices/expectation-device",
        headers=auth_headers,
        json={"is_active": True},
    ).status_code == 200
    db_session.expire_all()
    reactivated_at = db_session.get(Tank, tank["id"]).monitoring_expected_at
    assert reactivated_at is not None
    reactivated_at = reactivated_at.replace(tzinfo=timezone.utc) if reactivated_at.tzinfo is None else reactivated_at
    assert detect_monitoring_incidents(
        db_session, evaluated_at=reactivated_at + timedelta(seconds=899), grace_seconds=900
    ).created_incidents == 0
    assert detect_monitoring_incidents(
        db_session, evaluated_at=reactivated_at + timedelta(seconds=900), grace_seconds=900
    ).created_incidents == 1


def test_accepted_reading_recovers_incident_without_claiming_water_normal(
    client, auth_headers, db_session
):
    tank = _tank(client, auth_headers, "Recovery incident tank")
    device = _register(client, auth_headers, tank["id"], "recovery-device")
    ensure_default_thresholds(db_session)
    now = datetime(2026, 8, 22, 12, 0, tzinfo=timezone.utc)
    _make_overdue(db_session, tank["id"], now, seconds=900)
    detect_monitoring_incidents(db_session, evaluated_at=now, grace_seconds=900)

    recovery = ingest_reading(
        db_session,
        tank["id"],
        _values(31.0),
        device_id=device["device_id"],
        received_at=now + timedelta(seconds=1),
    )
    incident = db_session.scalar(select(MonitoringIncident))
    assert incident is not None
    assert incident.resolution_reason == "reporting_recovered"
    assert incident.recovery_reading_id == recovery.id
    assert incident.resolved_at == recovery.received_at
    critical_temperature = db_session.scalar(
        select(Alert).where(
            Alert.tank_id == tank["id"],
            Alert.parameter == "temperature",
            Alert.is_resolved.is_(False),
        )
    )
    assert critical_temperature is not None
    assert critical_temperature.severity.value == "critical"
    assert db_session.scalar(select(SecurityAuditEvent).where(SecurityAuditEvent.event_type == "monitoring_incident.resolve")) is not None
    assert db_session.scalar(select(SecurityAuditEvent).where(SecurityAuditEvent.event_type == "alert.auto_resolve")) is None


def test_invalid_reading_and_device_heartbeat_do_not_recover_incident(
    client, auth_headers, db_session
):
    tank = _tank(client, auth_headers, "No false recovery tank")
    device = _register(client, auth_headers, tank["id"], "no-false-recovery-device")
    now = datetime(2026, 8, 22, 12, 0, tzinfo=timezone.utc)
    _make_overdue(db_session, tank["id"], now, seconds=900)
    detect_monitoring_incidents(db_session, evaluated_at=now, grace_seconds=900)

    invalid = client.post(
        "/device-ingestion/readings",
        headers={"X-Device-Key": device["device_key"]},
        json={"temperature": 100, "ph": 7, "turbidity": 2, "tds": 150},
    )
    assert invalid.status_code == 422
    heartbeat = client.get(
        "/device-ingestion/actuators/pending",
        headers={"X-Device-Key": device["device_key"]},
    )
    assert heartbeat.status_code == 200
    db_session.expire_all()
    incident = db_session.scalar(select(MonitoringIncident))
    assert incident is not None and incident.resolved_at is None


def test_device_transitions_resolve_only_when_last_device_is_disabled(
    client, auth_headers, db_session
):
    tank = _tank(client, auth_headers, "Multi-device incident tank")
    first = _register(client, auth_headers, tank["id"], "multi-device-a")
    second = _register(client, auth_headers, tank["id"], "multi-device-b")
    now = datetime(2026, 8, 22, 12, 0, tzinfo=timezone.utc)
    _make_overdue(db_session, tank["id"], now, seconds=900)
    detect_monitoring_incidents(db_session, evaluated_at=now, grace_seconds=900)

    assert client.patch(f"/devices/{first['device_id']}", headers=auth_headers, json={"is_active": False}).status_code == 200
    db_session.expire_all()
    incident = db_session.scalar(select(MonitoringIncident))
    assert incident is not None and incident.resolved_at is None
    assert db_session.get(Tank, tank["id"]).monitoring_expected_at is not None

    assert client.patch(f"/devices/{second['device_id']}", headers=auth_headers, json={"is_active": False}).status_code == 200
    db_session.expire_all()
    incident = db_session.scalar(select(MonitoringIncident))
    assert incident is not None
    assert incident.resolution_reason == "monitoring_disabled"
    assert db_session.get(Tank, tank["id"]).monitoring_expected_at is None


def test_retirement_resolves_incident_and_prevents_new_detection(client, auth_headers, db_session):
    tank = _tank(client, auth_headers, "Retirement incident tank")
    _register(client, auth_headers, tank["id"], "retirement-incident-device")
    now = datetime(2026, 8, 22, 12, 0, tzinfo=timezone.utc)
    _make_overdue(db_session, tank["id"], now, seconds=900)
    detect_monitoring_incidents(db_session, evaluated_at=now, grace_seconds=900)

    retired = client.post(f"/tanks/{tank['id']}/retire", headers=auth_headers, json={})
    assert retired.status_code == 200
    incident = db_session.scalar(select(MonitoringIncident))
    assert incident is not None and incident.resolution_reason == "tank_retired"
    later = detect_monitoring_incidents(db_session, evaluated_at=now + timedelta(hours=1), grace_seconds=900)
    assert later.created_incidents == 0


def test_permanent_deletion_after_retirement_cascades_monitoring_incidents(
    client, auth_headers, db_session
):
    tank = _tank(client, auth_headers, "Delete incident history tank")
    _register(client, auth_headers, tank["id"], "delete-incident-device")
    now = datetime(2026, 8, 22, 12, 0, tzinfo=timezone.utc)
    _make_overdue(db_session, tank["id"], now, seconds=900)
    assert detect_monitoring_incidents(db_session, evaluated_at=now, grace_seconds=900).created_incidents == 1
    assert client.post(f"/tanks/{tank['id']}/retire", headers=auth_headers, json={}).status_code == 200
    assert client.delete(f"/tanks/{tank['id']}", headers=auth_headers).status_code == 204
    db_session.expire_all()
    assert db_session.scalar(select(MonitoringIncident.id)) is None


def test_outage_retirement_removes_public_access_rejects_device_and_retains_history_until_delete(
    client, auth_headers, db_session
):
    tank = _tank(client, auth_headers, "Cross-system lifecycle tank")
    device = _register(client, auth_headers, tank["id"], "cross-system-device")
    now = datetime(2026, 8, 22, 12, 0, tzinfo=timezone.utc)
    assert client.get(f"/public/tanks/{tank['public_id']}").status_code == 200
    _make_overdue(db_session, tank["id"], now, seconds=900)
    assert detect_monitoring_incidents(db_session, evaluated_at=now, grace_seconds=900).created_incidents == 1

    retired = client.post(f"/tanks/{tank['id']}/retire", headers=auth_headers, json={})
    assert retired.status_code == 200
    incident = db_session.scalar(select(MonitoringIncident).where(MonitoringIncident.tank_id == tank["id"]))
    assert incident is not None
    assert incident.resolution_reason == "tank_retired"
    assert client.get(f"/public/tanks/{tank['public_id']}").status_code == 404
    assert client.post(
        "/device-ingestion/readings",
        headers={"X-Device-Key": device["device_key"]},
        json={"temperature": 25, "ph": 7, "turbidity": 2, "tds": 150},
    ).status_code == 401

    retained_history = client.get(
        f"/tanks/{tank['id']}/monitoring-incidents?state=all&page=1&page_size=10",
        headers=auth_headers,
    )
    assert retained_history.status_code == 200
    assert retained_history.json()["total"] == 1
    assert client.delete(f"/tanks/{tank['id']}", headers=auth_headers).status_code == 204
    assert db_session.scalar(select(MonitoringIncident.id).where(MonitoringIncident.tank_id == tank["id"])) is None
    assert db_session.get(RegisteredDevice, device["device_id"]) is None


def test_incident_api_is_paginated_staff_read_only_and_distinct_from_alerts(
    client, auth_headers, db_session
):
    tank = _tank(client, auth_headers, "Incident API tank")
    _register(client, auth_headers, tank["id"], "incident-api-device")
    now = datetime(2026, 8, 22, 12, 0, tzinfo=timezone.utc)
    _make_overdue(db_session, tank["id"], now, seconds=900)
    detect_monitoring_incidents(db_session, evaluated_at=now, grace_seconds=900)

    active = client.get("/monitoring-incidents?page=1&page_size=1", headers=auth_headers)
    assert active.status_code == 200
    assert active.json()["total"] == 1
    assert active.json()["items"][0]["state"] == "active"
    assert active.json()["items"][0]["tank_name"] == tank["name"]
    scoped = client.get(
        f"/tanks/{tank['id']}/monitoring-incidents?state=all&page=1&page_size=1",
        headers=auth_headers,
    )
    assert scoped.status_code == 200
    assert scoped.json()["items"][0]["resolution_reason"] is None
    device = db_session.scalar(select(RegisteredDevice).where(RegisteredDevice.tank_id == tank["id"]))
    assert device is not None
    ingest_reading(
        db_session,
        tank["id"],
        _values(25.0),
        device_id=device.id,
        received_at=now + timedelta(seconds=1),
    )
    resolved = client.get(
        f"/monitoring-incidents?state=resolved&started_after={(now - timedelta(seconds=900)).isoformat().replace('+00:00', 'Z')}&page=1&page_size=1",
        headers=auth_headers,
    )
    assert resolved.status_code == 200
    assert resolved.json()["total"] == 1
    assert resolved.json()["items"][0]["resolution_reason"] == "reporting_recovered"
    assert client.get("/monitoring-incidents", headers={}).status_code == 401


def test_concurrent_detector_cycles_share_one_active_row(tmp_path: Path):
    engine = create_engine(
        f"sqlite:///{(tmp_path / 'monitoring-concurrency.db').as_posix()}",
        connect_args={"check_same_thread": False, "timeout": 10},
        future=True,
    )
    configure_sqlite_foreign_keys(engine)
    Base.metadata.create_all(bind=engine)
    session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False, future=True)
    now = datetime(2026, 8, 22, 12, 0, tzinfo=timezone.utc)
    setup = session_factory()
    tank = Tank(name="Concurrent incident tank", location="Rack", monitoring_expected_at=now - timedelta(seconds=900))
    setup.add(tank)
    setup.flush()
    setup.add(RegisteredDevice(id="concurrent-device", tank_id=tank.id, key_hash=hash_opaque_token("concurrent-key")))
    setup.commit()
    setup.close()

    barrier = Barrier(2)
    results: list[object] = []
    errors: list[BaseException] = []

    def run_cycle() -> None:
        db = session_factory()
        try:
            barrier.wait()
            results.append(detect_monitoring_incidents(db, evaluated_at=now, grace_seconds=900))
        except BaseException as exc:
            errors.append(exc)
        finally:
            db.close()

    threads = [Thread(target=run_cycle) for _ in range(2)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    assert not errors
    assert len(results) == 2
    check = session_factory()
    try:
        assert check.scalar(select(func.count()).select_from(MonitoringIncident)) == 1
    finally:
        check.close()
        Base.metadata.drop_all(bind=engine)
        engine.dispose()

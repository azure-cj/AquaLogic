from datetime import timedelta

import pytest
from sqlalchemy import func, select
from sqlalchemy.orm import sessionmaker

from app.models import (
    Alert,
    MonitoringIncident,
    PushDevice,
    PushNotificationDelivery,
    PushNotificationEvent,
    SensorReading,
    Tank,
)
from app.security import utc_now
from app.services.decision_engine import ensure_default_thresholds, ingest_reading
from app.services.monitoring_incidents import (
    detect_monitoring_incidents,
    resolve_active_monitoring_incident,
)
from app.services.push_notifications import PushDispatcher
from app.services.push_sender import PushConfigurationError, PushTransientError


class FailingPushSender:
    def __init__(self, error: Exception):
        self.error = error

    def send(self, **_kwargs):
        raise self.error


def _tank(db_session, name="M6.5 test tank"):
    tank = Tank(name=name, location="Test rack")
    db_session.add(tank)
    db_session.commit()
    db_session.refresh(tank)
    return tank


def _register_mobile_device(client, auth_headers, db_session):
    response = client.put(
        "/push/devices/current",
        headers=auth_headers,
        json={
            "installation_id": "65656565-6565-4565-8565-656565656565",
            "fcm_token": "m65-test-registration-token",
            "firebase_installation_id": "m65-test-firebase-installation",
            "firebase_installation_id_registered": True,
            "platform": "android",
        },
    )
    assert response.status_code == 200
    return db_session.scalar(select(PushDevice))


def _register_operational_device(client, auth_headers, tank):
    response = client.post(
        "/devices",
        headers=auth_headers,
        json={"tank_id": tank.id, "device_id": "m65-operational-device"},
    )
    assert response.status_code == 201
    return response.json()


def _reading_values(temperature=25.0):
    return {
        "temperature": temperature,
        "ph": 7.0,
        "turbidity": 2.0,
        "dissolved_oxygen": None,
        "tds": 150.0,
        "ammonia": None,
        "is_mock": False,
    }


def _events(db_session, event_type=None):
    statement = select(PushNotificationEvent).order_by(PushNotificationEvent.id)
    if event_type is not None:
        statement = statement.where(PushNotificationEvent.event_type == event_type)
    return list(db_session.scalars(statement).all())


def _delivery_count(db_session, event_id):
    return db_session.scalar(
        select(func.count())
        .select_from(PushNotificationDelivery)
        .where(PushNotificationDelivery.event_id == event_id)
    )


def _prepare_outage(client, auth_headers, db_session, *, name="M6.5 outage tank"):
    ensure_default_thresholds(db_session)
    tank = _tank(db_session, name)
    operational_device = _register_operational_device(client, auth_headers, tank)
    _register_mobile_device(client, auth_headers, db_session)

    detected_at = utc_now()
    tank_record = db_session.get(Tank, tank.id)
    assert tank_record is not None
    tank_record.monitoring_expected_at = detected_at - timedelta(seconds=900)
    db_session.commit()

    result = detect_monitoring_incidents(
        db_session,
        evaluated_at=detected_at,
        grace_seconds=900,
    )
    assert result.created_incidents == 1
    incident = db_session.scalar(
        select(MonitoringIncident).where(MonitoringIncident.tank_id == tank.id)
    )
    assert incident is not None
    return tank, operational_device, detected_at, incident


def test_alert_creation_enqueues_once_per_alert_identity(client, auth_headers, db_session):
    ensure_default_thresholds(db_session)
    tank = _tank(db_session, "Alert event lifecycle")
    _register_mobile_device(client, auth_headers, db_session)

    ingest_reading(db_session, tank.id, _reading_values(29.0))
    alert = db_session.scalar(
        select(Alert).where(Alert.tank_id == tank.id, Alert.parameter == "temperature")
    )
    assert alert is not None
    events = _events(db_session, "water_quality_alert")
    assert len(events) == 1
    assert events[0].event_key == f"water_quality_alert:{alert.id}:created"
    assert events[0].source_id == str(alert.id)
    assert _delivery_count(db_session, events[0].id) == 1

    # Escalation and later abnormal readings update this Alert identity only.
    ingest_reading(db_session, tank.id, _reading_values(31.0))
    db_session.refresh(alert)
    assert alert.severity.value == "critical"
    ingest_reading(db_session, tank.id, _reading_values(31.5))
    assert len(_events(db_session, "water_quality_alert")) == 1

    # Neither automatic resolution nor a repeated abnormal reading emits another event.
    ingest_reading(db_session, tank.id, _reading_values(25.0))
    db_session.refresh(alert)
    assert alert.is_resolved is True
    assert len(_events(db_session, "water_quality_alert")) == 1

    # A later genuinely new Alert identity receives its own creation event.
    ingest_reading(db_session, tank.id, _reading_values(31.0))
    alerts = list(
        db_session.scalars(
            select(Alert)
            .where(Alert.tank_id == tank.id, Alert.parameter == "temperature")
            .order_by(Alert.id)
        ).all()
    )
    events = _events(db_session, "water_quality_alert")
    assert len(alerts) == 2
    assert len(events) == 2
    assert [event.event_key for event in events] == [
        f"water_quality_alert:{item.id}:created" for item in alerts
    ]


def test_operator_resolution_does_not_enqueue_a_water_quality_resolution_push(
    client, auth_headers, db_session
):
    ensure_default_thresholds(db_session)
    tank = _tank(db_session, "Operator resolution event")
    _register_mobile_device(client, auth_headers, db_session)
    ingest_reading(db_session, tank.id, _reading_values(31.0))
    alert = db_session.scalar(
        select(Alert).where(Alert.tank_id == tank.id, Alert.parameter == "temperature")
    )
    assert alert is not None

    response = client.put(f"/alerts/{alert.id}/resolve", headers=auth_headers)
    assert response.status_code == 200
    events = _events(db_session)
    assert len(events) == 1
    assert events[0].event_type == "water_quality_alert"
    assert events[0].event_key == f"water_quality_alert:{alert.id}:created"


def test_alert_event_with_no_recipient_does_not_backfill_a_later_device(
    client, auth_headers, db_session
):
    ensure_default_thresholds(db_session)
    tank = _tank(db_session, "No recipient event")
    ingest_reading(db_session, tank.id, _reading_values(31.0))
    event = _events(db_session, "water_quality_alert")[0]
    assert _delivery_count(db_session, event.id) == 0

    _register_mobile_device(client, auth_headers, db_session)
    assert _delivery_count(db_session, event.id) == 0


def test_new_monitoring_outage_enqueues_once_and_snapshots_recipients(
    client, auth_headers, db_session
):
    tank, _device, detected_at, incident = _prepare_outage(
        client, auth_headers, db_session
    )
    events = _events(db_session, "monitoring_incident")
    assert len(events) == 1
    assert events[0].event_key == f"monitoring_incident:{incident.id}:opened"
    assert _delivery_count(db_session, events[0].id) == 1

    repeated = detect_monitoring_incidents(
        db_session,
        evaluated_at=detected_at + timedelta(minutes=1),
        grace_seconds=900,
    )
    assert repeated.created_incidents == 0
    assert len(_events(db_session, "monitoring_incident")) == 1
    assert _delivery_count(db_session, events[0].id) == 1
    assert incident.tank_id == tank.id


def test_reporting_recovery_enqueues_once_only_after_successful_transition(
    client, auth_headers, db_session
):
    tank, operational_device, detected_at, incident = _prepare_outage(
        client, auth_headers, db_session, name="M6.5 recovery tank"
    )

    ingest_reading(
        db_session,
        tank.id,
        _reading_values(25.0),
        device_id=operational_device["device_id"],
        received_at=detected_at + timedelta(seconds=1),
    )
    db_session.refresh(incident)
    assert incident.resolution_reason == "reporting_recovered"
    events = _events(db_session, "monitoring_recovered")
    assert len(events) == 1
    assert events[0].event_key == f"monitoring_incident:{incident.id}:recovered"
    assert _delivery_count(db_session, events[0].id) == 1

    assert (
        resolve_active_monitoring_incident(
            db_session,
            tank.id,
            reason="reporting_recovered",
            resolved_at=detected_at + timedelta(seconds=2),
        )
        is None
    )
    assert len(_events(db_session, "monitoring_recovered")) == 1


@pytest.mark.parametrize("closure", ["monitoring_disabled", "tank_retired"])
def test_administrative_monitoring_closure_does_not_send_recovered_push(
    client, auth_headers, db_session, closure
):
    tank, operational_device, _detected_at, incident = _prepare_outage(
        client,
        auth_headers,
        db_session,
        name=f"M6.5 {closure} tank",
    )

    if closure == "monitoring_disabled":
        response = client.patch(
            f"/devices/{operational_device['device_id']}",
            headers=auth_headers,
            json={"is_active": False},
        )
    else:
        response = client.post(
            f"/tanks/{tank.id}/retire",
            headers=auth_headers,
            json={},
        )
    assert response.status_code == 200
    db_session.refresh(incident)
    assert incident.resolution_reason == closure
    assert _events(db_session, "monitoring_recovered") == []
    assert len(_events(db_session)) == 1


@pytest.mark.parametrize(
    ("send_error", "expected_delivery_status"),
    [
        (PushConfigurationError(), "pending"),
        (PushTransientError(), "retry"),
    ],
)
def test_firebase_or_dispatch_failure_does_not_fail_sensor_ingestion(
    client,
    auth_headers,
    db_session,
    send_error,
    expected_delivery_status,
):
    ensure_default_thresholds(db_session)
    tank = _tank(db_session, "M6.5 failure isolation tank")
    operational_device = _register_operational_device(client, auth_headers, tank)
    _register_mobile_device(client, auth_headers, db_session)

    response = client.post(
        "/device-ingestion/readings",
        headers={"X-Device-Key": operational_device["device_key"]},
        json={"temperature": 31, "ph": 7, "turbidity": 2, "tds": 150},
    )
    assert response.status_code == 201
    reading_id = response.json()["id"]
    event = _events(db_session, "water_quality_alert")[0]
    db_session.rollback()

    factory = sessionmaker(
        bind=db_session.get_bind(),
        autoflush=False,
        autocommit=False,
        future=True,
    )
    dispatcher = PushDispatcher(
        enabled=True,
        interval_seconds=15,
        session_factory=factory,
        sender=FailingPushSender(send_error),
    )
    assert dispatcher.run_once(now=utc_now() + timedelta(seconds=5)) == 1

    db_session.expire_all()
    assert db_session.get(SensorReading, reading_id) is not None
    alert = db_session.scalar(
        select(Alert).where(Alert.tank_id == tank.id, Alert.parameter == "temperature")
    )
    assert alert is not None
    assert db_session.get(PushNotificationEvent, event.id) is not None
    delivery = db_session.scalar(
        select(PushNotificationDelivery).where(
            PushNotificationDelivery.event_id == event.id
        )
    )
    assert delivery is not None
    assert delivery.status == expected_delivery_status


def test_firebase_failure_does_not_rollback_monitoring_incident(
    client, auth_headers, db_session
):
    _tank_record, _device, detected_at, incident = _prepare_outage(
        client, auth_headers, db_session, name="M6.5 monitoring failure isolation"
    )
    event = _events(db_session, "monitoring_incident")[0]
    db_session.rollback()

    factory = sessionmaker(
        bind=db_session.get_bind(),
        autoflush=False,
        autocommit=False,
        future=True,
    )
    dispatcher = PushDispatcher(
        enabled=True,
        interval_seconds=15,
        session_factory=factory,
        sender=FailingPushSender(PushTransientError()),
    )
    assert dispatcher.run_once(now=detected_at + timedelta(seconds=5)) == 1

    db_session.expire_all()
    persisted_incident = db_session.get(MonitoringIncident, incident.id)
    assert persisted_incident is not None
    assert persisted_incident.resolved_at is None
    assert db_session.get(PushNotificationEvent, event.id) is not None
    delivery = db_session.scalar(
        select(PushNotificationDelivery).where(
            PushNotificationDelivery.event_id == event.id
        )
    )
    assert delivery is not None
    assert delivery.status == "retry"

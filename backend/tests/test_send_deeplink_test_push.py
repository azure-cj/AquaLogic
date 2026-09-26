from datetime import timedelta

import pytest
from sqlalchemy import func, select
from sqlalchemy.orm import sessionmaker

from app.cli.send_deeplink_test_push import main
from app.models import (
    Alert,
    AlertSeverity,
    MonitoringIncident,
    PushDevice,
    PushNotificationDelivery,
    PushNotificationEvent,
    Tank,
)
from app.security import utc_now


class FakePushSender:
    def __init__(self):
        self.calls = []

    def send(
        self,
        *,
        firebase_installation_id,
        fcm_token,
        title,
        body,
        data,
    ):
        self.calls.append(
            (firebase_installation_id, fcm_token, title, body, dict(data))
        )
        return "projects/test/messages/test-message-id"


def _factory(db_session):
    return sessionmaker(
        bind=db_session.get_bind(),
        autoflush=False,
        autocommit=False,
        future=True,
    )


def _register_device(client, auth_headers, db_session, *, suffix):
    fid = f"private-test-fid-{suffix}"
    token = f"private-test-fcm-token-{suffix}"
    response = client.put(
        "/push/devices/current",
        headers=auth_headers,
        json={
            "installation_id": f"88888888-8888-4888-8888-{suffix * 12}",
            "firebase_installation_id": fid,
            "firebase_installation_id_registered": True,
            "fcm_token": token,
            "platform": "android",
        },
    )
    assert response.status_code == 200
    device = db_session.scalar(
        select(PushDevice).where(PushDevice.firebase_installation_id == fid)
    )
    assert device is not None
    return device, fid, token


def _tank(db_session, *, name):
    tank = Tank(name=name, location="M6.6 test rack")
    db_session.add(tank)
    db_session.commit()
    db_session.refresh(tank)
    return tank


def _seed_record(db_session, *, kind):
    tank = _tank(db_session, name=f"M6.6 {kind} existing record")
    now = utc_now()
    if kind == "alert":
        record = Alert(
            tank_id=tank.id,
            reading_id=None,
            parameter="temperature",
            severity=AlertSeverity.warning,
            message="Existing alert used for navigation verification.",
            is_resolved=False,
        )
    else:
        resolved = kind == "recovery"
        record = MonitoringIncident(
            tank_id=tank.id,
            started_at=now - timedelta(hours=1),
            detected_at=now - timedelta(minutes=55),
            last_reading_received_at=now - timedelta(hours=1),
            resolved_at=now if resolved else None,
            resolution_reason="reporting_recovered" if resolved else None,
            recovery_reading_id=None,
        )
    db_session.add(record)
    db_session.commit()
    db_session.refresh(record)
    return tank, record


@pytest.mark.parametrize(
    ("kind", "event_type", "id_key", "event_key"),
    [
        (
            "alert",
            "water_quality_alert",
            "alert_id",
            "water_quality_alert:{record_id}:created",
        ),
        (
            "monitoring",
            "monitoring_incident",
            "incident_id",
            "monitoring_incident:{record_id}:opened",
        ),
        (
            "recovery",
            "monitoring_recovered",
            "incident_id",
            "monitoring_incident:{record_id}:recovered",
        ),
    ],
)
def test_deeplink_test_push_uses_existing_record_and_one_fid_target(
    client, auth_headers, db_session, *, kind, event_type, id_key, event_key
):
    tank, record = _seed_record(db_session, kind=kind)
    first_device, first_fid, first_token = _register_device(
        client, auth_headers, db_session, suffix="1"
    )
    second_device, second_fid, second_token = _register_device(
        client, auth_headers, db_session, suffix="2"
    )
    sender = FakePushSender()
    out = []
    err = []

    result = main(
        ["--kind", kind, "--confirm"],
        session_factory=_factory(db_session),
        sender=sender,
        push_enabled=True,
        stdout=out.append,
        stderr=err.append,
    )

    db_session.expire_all()
    event = db_session.scalar(select(PushNotificationEvent))
    delivery = db_session.scalar(select(PushNotificationDelivery))
    assert result == 0
    assert err == []
    assert len(sender.calls) == 1
    assert sender.calls[0][0] == second_fid
    assert sender.calls[0][1] is None
    assert sender.calls[0][2].startswith("AquaLogic M6.6")
    assert sender.calls[0][4] == {
        "schema_version": "1",
        "type": event_type,
        "event_key": event_key.format(record_id=record.id),
        "tank_id": str(tank.id),
        id_key: str(record.id),
    }
    assert event.source_type == "manual_test"
    assert event.source_id == str(record.id)
    assert event.payload == sender.calls[0][4]
    assert delivery.push_device_id == second_device.id
    assert delivery.status == "sent"
    assert first_device.id != second_device.id
    assert first_fid not in "\n".join(out + err)
    assert second_fid not in "\n".join(out + err)
    assert first_token not in "\n".join(out + err)
    assert second_token not in "\n".join(out + err)
    assert "test notification sent" in out[0]
    assert (
        db_session.scalar(
            select(func.count()).select_from(Alert).where(Alert.tank_id == tank.id)
        )
        == int(kind == "alert")
    )
    assert (
        db_session.scalar(
            select(func.count())
            .select_from(MonitoringIncident)
            .where(MonitoringIncident.tank_id == tank.id)
        )
        == int(kind != "alert")
    )


def test_deeplink_test_push_requires_confirmation_and_enabled_flag(db_session):
    sender = FakePushSender()
    factory = _factory(db_session)
    err = []

    unconfirmed = main(
        ["--kind", "alert"],
        session_factory=factory,
        sender=sender,
        push_enabled=True,
        stderr=err.append,
    )
    disabled = main(
        ["--kind", "alert", "--confirm"],
        session_factory=factory,
        sender=sender,
        push_enabled=False,
        stderr=err.append,
    )

    assert unconfirmed == 2
    assert disabled == 2
    assert sender.calls == []
    assert db_session.scalar(select(func.count()).select_from(PushNotificationEvent)) == 0
    assert db_session.scalar(select(func.count()).select_from(PushNotificationDelivery)) == 0


def test_deeplink_test_push_requires_matching_existing_record_and_fid_device(
    client, auth_headers, db_session
):
    _, _record = _seed_record(db_session, kind="recovery")
    # A token-only legacy registration is deliberately ineligible for this test.
    response = client.put(
        "/push/devices/current",
        headers=auth_headers,
        json={
            "installation_id": "99999999-9999-4999-8999-999999999999",
            "firebase_installation_id": None,
            "firebase_installation_id_registered": False,
            "fcm_token": "private-legacy-token-only",
            "platform": "android",
        },
    )
    assert response.status_code == 200
    sender = FakePushSender()
    err = []

    no_active_outage = main(
        ["--kind", "monitoring", "--confirm"],
        session_factory=_factory(db_session),
        sender=sender,
        push_enabled=True,
        stderr=err.append,
    )
    no_fid_recipient = main(
        ["--kind", "recovery", "--confirm"],
        session_factory=_factory(db_session),
        sender=sender,
        push_enabled=True,
        stderr=err.append,
    )

    assert no_active_outage == 1
    assert no_fid_recipient == 1
    assert sender.calls == []
    assert db_session.scalar(select(func.count()).select_from(PushNotificationEvent)) == 0
    assert db_session.scalar(select(func.count()).select_from(PushNotificationDelivery)) == 0
    assert "private-legacy-token-only" not in "\n".join(err)


def test_deterministic_event_key_prevents_a_repeat_send(
    client, auth_headers, db_session
):
    _tank_record, record = _seed_record(db_session, kind="alert")
    _register_device(client, auth_headers, db_session, suffix="3")
    factory = _factory(db_session)
    first_sender = FakePushSender()
    second_sender = FakePushSender()
    err = []

    first = main(
        ["--kind", "alert", "--confirm"],
        session_factory=factory,
        sender=first_sender,
        push_enabled=True,
        stderr=err.append,
    )
    second = main(
        ["--kind", "alert", "--confirm"],
        session_factory=factory,
        sender=second_sender,
        push_enabled=True,
        stderr=err.append,
    )

    assert first == 0
    assert second == 2
    assert len(first_sender.calls) == 1
    assert second_sender.calls == []
    event = db_session.scalar(select(PushNotificationEvent))
    assert event.event_key == f"water_quality_alert:{record.id}:created"
    assert db_session.scalar(select(func.count()).select_from(PushNotificationEvent)) == 1
    assert db_session.scalar(select(func.count()).select_from(PushNotificationDelivery)) == 1

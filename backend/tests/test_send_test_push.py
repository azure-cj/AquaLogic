from sqlalchemy import func, select
from sqlalchemy.orm import sessionmaker

from app.cli.send_test_push import main
from app.models import (
    PushDevice,
    PushNotificationDelivery,
    PushNotificationEvent,
)
from app.services.push_sender import PushTransientError


class FakePushSender:
    def __init__(self, outcome=None):
        self.outcome = outcome
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
        if isinstance(self.outcome, Exception):
            raise self.outcome
        return self.outcome or "projects/test/messages/test-message-id"


def _factory(db_session):
    return sessionmaker(
        bind=db_session.get_bind(),
        autoflush=False,
        autocommit=False,
        future=True,
    )


def _register_device(client, auth_headers, db_session, *, fid, token):
    response = client.put(
        "/push/devices/current",
        headers=auth_headers,
        json={
            "installation_id": "11111111-1111-4111-8111-111111111111",
            "firebase_installation_id": fid,
            "firebase_installation_id_registered": fid is not None,
            "fcm_token": token,
            "platform": "android",
        },
    )
    assert response.status_code == 200
    device = db_session.scalar(select(PushDevice))
    assert device is not None
    return device


def test_confirmed_test_push_uses_one_fid_target_and_records_outbox(
    client, auth_headers, db_session
):
    fid = "private-test-fid-value"
    token = "private-test-fcm-token-value"
    _register_device(client, auth_headers, db_session, fid=fid, token=token)
    sender = FakePushSender()
    out = []
    err = []
    request_id = "32d3594c-7149-46ec-9f74-d33f214355c7"

    result = main(
        ["--request-id", request_id, "--confirm"],
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
    assert sender.calls[0][0] == fid
    assert sender.calls[0][1] is None
    assert sender.calls[0][2:4] == (
        "AquaLogic Push Test",
        "Railway → Firebase → Android is working.",
    )
    assert sender.calls[0][4] == {
        "schema_version": "1",
        "type": "test_push",
        "event_key": f"test_push:{request_id}",
    }
    assert event.event_key == f"test_push:{request_id}"
    assert event.event_type == "test_push"
    assert event.tank_id is None
    assert delivery.event_id == event.id
    assert delivery.push_device_id == db_session.scalar(select(PushDevice.id))
    assert delivery.status == "sent"
    assert delivery.firebase_message_id == "projects/test/messages/test-message-id"
    assert fid not in "\n".join(out + err)
    assert token not in "\n".join(out + err)
    assert db_session.scalar(select(func.count()).select_from(PushNotificationEvent)) == 1
    assert db_session.scalar(select(func.count()).select_from(PushNotificationDelivery)) == 1


def test_test_push_requires_confirm_and_enabled_flag_without_creating_event(
    db_session,
):
    sender = FakePushSender()
    out = []
    err = []
    factory = _factory(db_session)
    request_id = "32d3594c-7149-46ec-9f74-d33f214355c8"

    unconfirmed = main(
        ["--request-id", request_id],
        session_factory=factory,
        sender=sender,
        push_enabled=True,
        stdout=out.append,
        stderr=err.append,
    )
    disabled = main(
        ["--request-id", request_id, "--confirm"],
        session_factory=factory,
        sender=sender,
        push_enabled=False,
        stdout=out.append,
        stderr=err.append,
    )

    assert unconfirmed == 2
    assert disabled == 2
    assert len(sender.calls) == 0
    assert db_session.scalar(select(func.count()).select_from(PushNotificationEvent)) == 0
    assert db_session.scalar(select(func.count()).select_from(PushNotificationDelivery)) == 0


def test_test_push_refuses_legacy_device_without_fid(
    client, auth_headers, db_session
):
    _register_device(
        client,
        auth_headers,
        db_session,
        fid=None,
        token="private-legacy-fcm-token-value",
    )
    sender = FakePushSender()
    err = []

    result = main(
        ["--request-id", "32d3594c-7149-46ec-9f74-d33f214355c9", "--confirm"],
        session_factory=_factory(db_session),
        sender=sender,
        push_enabled=True,
        stderr=err.append,
    )

    assert result == 1
    assert len(sender.calls) == 0
    assert "private-legacy-fcm-token-value" not in "\n".join(err)
    assert db_session.scalar(select(func.count()).select_from(PushNotificationEvent)) == 0


def test_same_request_id_is_never_sent_twice(client, auth_headers, db_session):
    fid = "private-test-fid-value"
    token = "private-test-fcm-token-value"
    _register_device(client, auth_headers, db_session, fid=fid, token=token)
    factory = _factory(db_session)
    request_id = "32d3594c-7149-46ec-9f74-d33f214355ca"
    first_sender = FakePushSender()
    second_sender = FakePushSender()
    err = []

    first = main(
        ["--request-id", request_id, "--confirm"],
        session_factory=factory,
        sender=first_sender,
        push_enabled=True,
        stderr=err.append,
    )
    second = main(
        ["--request-id", request_id, "--confirm"],
        session_factory=factory,
        sender=second_sender,
        push_enabled=True,
        stderr=err.append,
    )

    assert first == 0
    assert second == 2
    assert len(first_sender.calls) == 1
    assert second_sender.calls == []
    assert db_session.scalar(select(func.count()).select_from(PushNotificationEvent)) == 1
    assert db_session.scalar(select(func.count()).select_from(PushNotificationDelivery)) == 1


def test_failed_test_send_leaves_safe_retry_state_without_identifiers(
    client, auth_headers, db_session
):
    fid = "private-test-fid-value"
    token = "private-test-fcm-token-value"
    _register_device(client, auth_headers, db_session, fid=fid, token=token)
    err = []

    result = main(
        ["--request-id", "32d3594c-7149-46ec-9f74-d33f214355cb", "--confirm"],
        session_factory=_factory(db_session),
        sender=FakePushSender(PushTransientError()),
        push_enabled=True,
        stderr=err.append,
    )

    db_session.expire_all()
    delivery = db_session.scalar(select(PushNotificationDelivery))
    output = "\n".join(err)
    assert result == 1
    assert delivery.status == "retry"
    assert delivery.last_error_code == "firebase_transient_error"
    assert fid not in output
    assert token not in output

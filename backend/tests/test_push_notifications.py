import base64
import json
import logging
from dataclasses import replace
from datetime import timedelta

import pytest
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import sessionmaker

from app.models import (
    Alert,
    AlertSeverity,
    AuthSession,
    PushDevice,
    PushNotificationDelivery,
    PushNotificationEvent,
    Tank,
)
from app.security import utc_now
from app.services import push_notifications
from app.services.push_notifications import (
    _dispatch_claim,
    PushDispatcher,
    claim_due_deliveries,
    enqueue_push_notification,
)
from app.services.push_sender import (
    FirebaseAdminPushSender,
    PushPermanentRecipientError,
    PushTransientError,
)


class FakePushSender:
    def __init__(self, outcome=None):
        self.outcome = outcome
        self.calls = []

    def send(
        self,
        *,
        firebase_installation_id=None,
        fcm_token=None,
        title,
        body,
        data,
    ):
        self.calls.append((firebase_installation_id, fcm_token, title, body, dict(data)))
        if isinstance(self.outcome, Exception):
            raise self.outcome
        return self.outcome or "projects/test/messages/fake-message-id"


def _factory(db_session):
    return sessionmaker(
        bind=db_session.get_bind(),
        autoflush=False,
        autocommit=False,
        future=True,
    )


def _registered_device(
    client, auth_headers, db_session, *, token="test-fcm-token", fid=None
):
    payload = {
        "installation_id": "11111111-1111-4111-8111-111111111111",
        "fcm_token": token,
        "platform": "android",
    }
    if fid is not None:
        payload["firebase_installation_id"] = fid
    response = client.put(
        "/push/devices/current",
        headers=auth_headers,
        json=payload,
    )
    assert response.status_code == 200
    device = db_session.scalar(select(PushDevice))
    assert device is not None
    return device


def _tank(db_session):
    tank = Tank(name="Push test tank", location="Lab")
    db_session.add(tank)
    db_session.commit()
    db_session.refresh(tank)
    return tank


def _enqueue(db_session, tank, *, source_id=37):
    return enqueue_push_notification(
        db_session,
        event_type="water_quality_alert",
        source_id=source_id,
        tank_id=tank.id,
        title="Water-quality alert",
        body="A test tank needs attention. Open AquaLogic for details.",
    )


def _delivery(db_session):
    return db_session.scalar(select(PushNotificationDelivery))


def test_push_disabled_and_missing_secret_leave_health_available(
    client, monkeypatch
):
    monkeypatch.delenv("FIREBASE_SERVICE_ACCOUNT_JSON_B64", raising=False)
    monkeypatch.setattr(
        push_notifications,
        "settings",
        replace(push_notifications.settings, push_notifications_enabled=False),
    )
    assert push_notifications.start_push_dispatcher() is None
    dispatcher = PushDispatcher(
        enabled=False,
        interval_seconds=15,
        sender=FirebaseAdminPushSender(),
    )

    assert dispatcher.run_once() == 0
    assert client.get("/health").status_code == 200


def test_enabled_startup_with_missing_secret_is_sanitized_and_nonfatal(
    client, monkeypatch, caplog
):
    caplog.set_level(logging.DEBUG)
    monkeypatch.delenv("FIREBASE_SERVICE_ACCOUNT_JSON_B64", raising=False)
    dispatcher = PushDispatcher(enabled=True, interval_seconds=15)

    dispatcher.start()
    try:
        assert dispatcher.configuration_blocked is True
        assert dispatcher.run_once() == 0
        assert client.get("/health").status_code == 200
        assert "firebase_configuration_error" in caplog.text
        assert "private_key" not in caplog.text
    finally:
        dispatcher.stop()


def test_fake_sender_success_stores_only_message_result(
    client, auth_headers, db_session
):
    device = _registered_device(client, auth_headers, db_session)
    tank = _tank(db_session)
    event, created = _enqueue(db_session, tank)
    db_session.commit()
    sender = FakePushSender()
    dispatcher = PushDispatcher(
        enabled=True,
        interval_seconds=15,
        session_factory=_factory(db_session),
        sender=sender,
    )

    assert created is True
    assert dispatcher.run_once(now=utc_now() + timedelta(seconds=1)) == 1
    db_session.expire_all()
    delivery = _delivery(db_session)
    assert delivery.status == "sent"
    assert delivery.firebase_message_id == "projects/test/messages/fake-message-id"
    assert delivery.sent_at is not None
    assert sender.calls[0][0] is None
    assert sender.calls[0][1] == device.fcm_token
    assert sender.calls[0][4] == {
        "schema_version": "1",
        "type": "water_quality_alert",
        "event_key": f"water_quality_alert:{event.source_id}:created",
        "tank_id": str(tank.id),
        "alert_id": event.source_id,
    }


def test_unregistered_token_permanently_fails_and_disables_only_matching_device(
    client, auth_headers, db_session
):
    device = _registered_device(client, auth_headers, db_session)
    tank = _tank(db_session)
    _enqueue(db_session, tank)
    db_session.commit()
    dispatcher = PushDispatcher(
        enabled=True,
        interval_seconds=15,
        session_factory=_factory(db_session),
        sender=FakePushSender(PushPermanentRecipientError()),
    )

    dispatcher.run_once(now=utc_now() + timedelta(seconds=1))
    db_session.expire_all()
    assert db_session.get(PushDevice, device.id).is_active is False
    assert _delivery(db_session).status == "permanent_failed"
    assert _delivery(db_session).last_error_code == "unregistered_push_recipient"


def test_dispatch_prefers_fid_when_both_distinct_identifiers_are_registered(
    client, auth_headers, db_session
):
    device = _registered_device(
        client,
        auth_headers,
        db_session,
        token="separate-fcm-registration-token",
        fid="preferred-firebase-installation-id",
    )
    tank = _tank(db_session)
    _enqueue(db_session, tank)
    db_session.commit()
    sender = FakePushSender()
    dispatcher = PushDispatcher(
        enabled=True,
        interval_seconds=15,
        session_factory=_factory(db_session),
        sender=sender,
    )

    dispatcher.run_once(now=utc_now() + timedelta(seconds=1))

    assert sender.calls[0][0] == device.firebase_installation_id
    assert sender.calls[0][1] is None


def test_unregistered_fid_deactivates_only_the_matching_current_fid(
    client, auth_headers, db_session
):
    device = _registered_device(
        client,
        auth_headers,
        db_session,
        fid="targeted-firebase-installation-id",
    )
    tank = _tank(db_session)
    _enqueue(db_session, tank)
    db_session.commit()
    dispatcher = PushDispatcher(
        enabled=True,
        interval_seconds=15,
        session_factory=_factory(db_session),
        sender=FakePushSender(PushPermanentRecipientError()),
    )

    dispatcher.run_once(now=utc_now() + timedelta(seconds=1))
    db_session.expire_all()

    assert db_session.get(PushDevice, device.id).is_active is False
    assert _delivery(db_session).last_error_code == "unregistered_push_recipient"


def test_transient_failure_schedules_bounded_retry_without_disabling_device(
    client, auth_headers, db_session
):
    device = _registered_device(client, auth_headers, db_session)
    tank = _tank(db_session)
    _enqueue(db_session, tank)
    db_session.commit()
    attempt_at = utc_now() + timedelta(seconds=2)
    dispatcher = PushDispatcher(
        enabled=True,
        interval_seconds=15,
        session_factory=_factory(db_session),
        sender=FakePushSender(PushTransientError()),
    )

    dispatcher.run_once(now=attempt_at)
    db_session.expire_all()
    delivery = _delivery(db_session)
    assert delivery.status == "retry"
    assert delivery.attempt_count == 1
    assert delivery.next_attempt_at.replace(tzinfo=attempt_at.tzinfo) == attempt_at + timedelta(seconds=30)
    assert db_session.get(PushDevice, device.id).is_active is True


def test_transient_retries_stop_at_the_configured_attempt_cap(
    client, auth_headers, db_session
):
    device = _registered_device(client, auth_headers, db_session)
    tank = _tank(db_session)
    _enqueue(db_session, tank)
    db_session.commit()
    started_at = utc_now()
    sender = FakePushSender(PushTransientError())
    dispatcher = PushDispatcher(
        enabled=True,
        interval_seconds=15,
        session_factory=_factory(db_session),
        sender=sender,
    )
    at = started_at
    for attempt in range(5):
        dispatcher.run_once(now=at)
        if attempt < 4:
            at += timedelta(seconds=30 * (2**attempt) + 1)

    db_session.expire_all()
    delivery = _delivery(db_session)
    assert delivery.status == "permanent_failed"
    assert delivery.attempt_count == 5
    assert delivery.last_error_code == "attempts_exhausted"
    assert len(sender.calls) == 5
    assert db_session.get(PushDevice, device.id).is_active is True


@pytest.mark.parametrize("ineligible_state", ["revoked", "expired", "inactive", "disabled", "role"])
def test_dispatch_rechecks_recipient_eligibility(
    client, auth_headers, test_user, db_session, ineligible_state
):
    device = _registered_device(client, auth_headers, db_session)
    tank = _tank(db_session)
    _enqueue(db_session, tank)
    session = db_session.get(AuthSession, device.auth_session_id)
    if ineligible_state == "revoked":
        session.revoked_at = utc_now()
    elif ineligible_state == "expired":
        session.expires_at = utc_now() - timedelta(seconds=1)
    elif ineligible_state == "inactive":
        test_user.is_active = False
    elif ineligible_state == "disabled":
        device.is_active = False
    elif ineligible_state == "role":
        test_user.role = "owner"
    db_session.commit()
    sender = FakePushSender()
    dispatcher = PushDispatcher(
        enabled=True,
        interval_seconds=15,
        session_factory=_factory(db_session),
        sender=sender,
    )

    dispatcher.run_once(now=utc_now() + timedelta(seconds=1))
    db_session.expire_all()
    assert sender.calls == []
    assert _delivery(db_session).status == "skipped"


def test_missing_or_invalid_global_credentials_are_sanitized_and_do_not_disable_device(
    client, auth_headers, db_session, monkeypatch, caplog
):
    caplog.set_level(logging.DEBUG)
    token = "device-token-must-not-be-logged"
    device = _registered_device(client, auth_headers, db_session, token=token)
    tank = _tank(db_session)
    _enqueue(db_session, tank)
    db_session.commit()
    monkeypatch.delenv("FIREBASE_SERVICE_ACCOUNT_JSON_B64", raising=False)
    monkeypatch.delenv("FIREBASE_PROJECT_ID", raising=False)
    dispatcher = PushDispatcher(
        enabled=True,
        interval_seconds=15,
        session_factory=_factory(db_session),
        sender=FirebaseAdminPushSender(),
    )

    dispatcher.run_once(now=utc_now() + timedelta(seconds=1))
    db_session.expire_all()
    delivery = _delivery(db_session)
    assert delivery.status == "pending"
    assert delivery.attempt_count == 0
    assert delivery.last_error_code == "firebase_configuration_error"
    assert db_session.get(PushDevice, device.id).is_active is True
    assert token not in caplog.text
    assert dispatcher.configuration_blocked is True

    credential_marker = "PRIVATE_CREDENTIAL_MARKER_MUST_NOT_APPEAR"
    malformed_credential = json.dumps(
        {
            "type": "service_account",
            "project_id": "aqualogic-test",
            "private_key": credential_marker,
        }
    ).encode()
    monkeypatch.setenv(
        "FIREBASE_SERVICE_ACCOUNT_JSON_B64",
        base64.b64encode(malformed_credential).decode("ascii"),
    )
    restarted_dispatcher = PushDispatcher(
        enabled=True,
        interval_seconds=15,
        session_factory=_factory(db_session),
        sender=FirebaseAdminPushSender(),
    )
    restarted_dispatcher.run_once(now=utc_now() + timedelta(seconds=62))
    db_session.expire_all()
    assert _delivery(db_session).status == "pending"
    assert db_session.get(PushDevice, device.id).is_active is True
    assert credential_marker not in caplog.text
    assert token not in caplog.text


def test_firebase_admin_sender_builds_notification_and_maps_unregistered_error(monkeypatch):
    from firebase_admin import messaging

    token = "separate-fcm-registration-token"
    fid = "fake-firebase-installation-id"
    sender = FirebaseAdminPushSender()
    app = object()
    monkeypatch.setattr(sender, "_get_app", lambda: app)
    sent = {}

    def fake_send(message, *, app):
        sent["app"] = app
        sent["message"] = message
        return "projects/test/messages/fake-sdk-id"

    monkeypatch.setattr(messaging, "send", fake_send)
    result = sender.send(
        firebase_installation_id=fid,
        fcm_token=token,
        title="Water-quality alert",
        body="Open AquaLogic for details.",
        data={"schema_version": "1", "type": "water_quality_alert"},
    )
    assert result == "projects/test/messages/fake-sdk-id"
    assert sent["app"] is app
    assert sent["message"].fid == fid
    assert sent["message"].token is None
    assert sent["message"].notification.title == "Water-quality alert"
    assert sent["message"].notification.body == "Open AquaLogic for details."
    assert sent["message"].data == {"schema_version": "1", "type": "water_quality_alert"}

    result = sender.send(
        firebase_installation_id=None,
        fcm_token=token,
        title="Compatibility alert",
        body="Open AquaLogic for details.",
        data={"schema_version": "1", "type": "water_quality_alert"},
    )
    assert result == "projects/test/messages/fake-sdk-id"
    assert sent["message"].fid is None
    assert sent["message"].token == token

    def unregistered_send(message, *, app):
        raise messaging.UnregisteredError(f"provider error included {token}")

    monkeypatch.setattr(messaging, "send", unregistered_send)
    with pytest.raises(PushPermanentRecipientError) as error:
        sender.send(
            firebase_installation_id=fid,
            fcm_token=token,
            title="Water-quality alert",
            body="Open AquaLogic for details.",
            data={"schema_version": "1", "type": "water_quality_alert"},
        )
    assert token not in str(error.value)


def test_ineligible_devices_are_not_materialized_as_recipients(
    client, auth_headers, db_session
):
    device = _registered_device(client, auth_headers, db_session)
    session = db_session.get(AuthSession, device.auth_session_id)
    session.revoked_at = utc_now()
    tank = _tank(db_session)

    event, created = _enqueue(db_session, tank)
    db_session.commit()

    assert created is True
    assert db_session.scalar(
        select(func.count()).select_from(PushNotificationDelivery).where(
            PushNotificationDelivery.event_id == event.id
        )
    ) == 0


def test_monitoring_recovery_uses_the_versioned_payload_and_stable_event_key(
    db_session,
):
    tank = _tank(db_session)
    event, created = enqueue_push_notification(
        db_session,
        event_type="monitoring_recovered",
        source_id=77,
        tank_id=tank.id,
        title="Monitoring restored",
        body="Reporting has resumed. Open AquaLogic for details.",
    )

    assert created is True
    assert event.event_key == "monitoring_incident:77:recovered"
    assert event.payload == {
        "schema_version": "1",
        "type": "monitoring_recovered",
        "event_key": "monitoring_incident:77:recovered",
        "tank_id": str(tank.id),
        "incident_id": "77",
    }
    assert all(isinstance(value, str) for value in event.payload.values())


def test_duplicate_logical_event_key_creates_only_one_event_and_delivery(
    client, auth_headers, db_session
):
    _registered_device(client, auth_headers, db_session)
    tank = _tank(db_session)
    first, first_created = _enqueue(db_session, tank, source_id=91)
    second, second_created = _enqueue(db_session, tank, source_id=91)
    db_session.commit()

    assert first_created is True
    assert second_created is False
    assert first.id == second.id
    assert db_session.scalar(select(func.count()).select_from(PushNotificationEvent)) == 1
    assert db_session.scalar(select(func.count()).select_from(PushNotificationDelivery)) == 1


def test_event_device_delivery_pair_is_unique(
    client, auth_headers, db_session
):
    device = _registered_device(client, auth_headers, db_session)
    tank = _tank(db_session)
    event, _ = _enqueue(db_session, tank)
    db_session.commit()

    with pytest.raises(IntegrityError):
        with db_session.begin_nested():
            db_session.add(
                PushNotificationDelivery(
                    event_id=event.id,
                    push_device_id=device.id,
                    status="pending",
                    attempt_count=0,
                    next_attempt_at=utc_now(),
                )
            )
            db_session.flush()
    assert db_session.scalar(select(func.count()).select_from(PushNotificationDelivery)) == 1


def test_crashed_lease_is_recovered_by_a_later_dispatcher(
    client, auth_headers, db_session
):
    _registered_device(client, auth_headers, db_session)
    tank = _tank(db_session)
    _enqueue(db_session, tank)
    db_session.commit()
    started_at = utc_now()
    first_claim = claim_due_deliveries(_factory(db_session), now=started_at)[0]
    assert claim_due_deliveries(
        _factory(db_session), now=started_at + timedelta(seconds=90)
    ) == []
    db_session.expire_all()
    assert _delivery(db_session).status == "sending"
    assert _delivery(db_session).attempt_count == 1

    factory = _factory(db_session)
    second_claim = claim_due_deliveries(
        factory,
        now=started_at + timedelta(seconds=181),
    )[0]
    assert second_claim.lock_token != first_claim.lock_token
    sender = FakePushSender()
    assert _dispatch_claim(
        factory,
        sender,
        second_claim,
        now=started_at + timedelta(seconds=181),
    ) is False
    db_session.expire_all()
    delivery = _delivery(db_session)
    assert delivery.status == "sent"
    assert delivery.attempt_count == 2
    assert sender.calls


def test_delivery_failure_never_rolls_back_source_alert(
    client, auth_headers, db_session
):
    _registered_device(client, auth_headers, db_session)
    tank = _tank(db_session)
    alert = Alert(
        tank_id=tank.id,
        parameter="ph",
        severity=AlertSeverity.warning,
        message="pH test alert",
    )
    db_session.add(alert)
    db_session.flush()
    enqueue_push_notification(
        db_session,
        event_type="water_quality_alert",
        source_id=alert.id,
        tank_id=tank.id,
        title="Water-quality alert",
        body="A test tank needs attention. Open AquaLogic for details.",
    )
    db_session.commit()

    dispatcher = PushDispatcher(
        enabled=True,
        interval_seconds=15,
        session_factory=_factory(db_session),
        sender=FakePushSender(PushTransientError()),
    )
    dispatcher.run_once(now=utc_now() + timedelta(seconds=1))
    db_session.expire_all()
    assert db_session.get(Alert, alert.id) is not None
    assert _delivery(db_session).status == "retry"


def test_enqueue_stays_in_source_transaction_and_rolls_back_with_it(
    client, auth_headers, db_session
):
    _registered_device(client, auth_headers, db_session)
    tank = _tank(db_session)
    alert = Alert(
        tank_id=tank.id,
        parameter="ph",
        severity=AlertSeverity.warning,
        message="rollback test alert",
    )
    db_session.add(alert)
    db_session.flush()
    enqueue_push_notification(
        db_session,
        event_type="water_quality_alert",
        source_id=alert.id,
        tank_id=tank.id,
        title="Water-quality alert",
        body="A test tank needs attention. Open AquaLogic for details.",
    )
    db_session.rollback()

    assert db_session.scalar(select(func.count()).select_from(Alert)) == 0
    assert db_session.scalar(select(func.count()).select_from(PushNotificationEvent)) == 0
    assert db_session.scalar(select(func.count()).select_from(PushNotificationDelivery)) == 0


def test_outbox_integrity_failure_does_not_abort_source_alert_transaction(
    db_session, monkeypatch, caplog
):
    tank = _tank(db_session)
    alert = Alert(
        tank_id=tank.id,
        parameter="ph",
        severity=AlertSeverity.warning,
        message="outbox isolation test alert",
    )
    db_session.add(alert)
    db_session.flush()
    monkeypatch.setattr(
        push_notifications,
        "eligible_push_device_ids",
        lambda db, now: [999999],
    )

    event, created = enqueue_push_notification(
        db_session,
        event_type="water_quality_alert",
        source_id=alert.id,
        tank_id=tank.id,
        title="Water-quality alert",
        body="Open AquaLogic for details.",
    )
    db_session.commit()

    assert event is None
    assert created is False
    assert db_session.get(Alert, alert.id) is not None
    assert db_session.scalar(select(func.count()).select_from(PushNotificationEvent)) == 0
    assert db_session.scalar(select(func.count()).select_from(PushNotificationDelivery)) == 0
    assert "outbox_integrity_error" in caplog.text


def test_push_disabled_dispatcher_does_not_claim_pending_rows(
    client, auth_headers, db_session
):
    _registered_device(client, auth_headers, db_session)
    tank = _tank(db_session)
    _enqueue(db_session, tank)
    db_session.commit()
    dispatcher = PushDispatcher(enabled=False, interval_seconds=15, sender=FakePushSender())

    assert dispatcher.run_once() == 0
    assert _delivery(db_session).status == "pending"

"""Send one controlled M6.4 push to the latest eligible admin installation.

The command has no target-user, device-token, or Firebase-identifier arguments.
It creates a uniquely keyed outbox event and reserves its single delivery before
calling the normal dispatcher delivery path.
"""

import argparse
import sys
import uuid
from dataclasses import dataclass
from datetime import datetime
from typing import Callable, Sequence

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.config import settings
from app.database import SessionLocal
from app.models import (
    AuthSession,
    PushDevice,
    PushNotificationDelivery,
    PushNotificationEvent,
    User,
)
from app.security import utc_now
from app.services.push_notifications import DeliveryClaim, _dispatch_claim
from app.services.push_sender import FirebaseAdminPushSender, PushSender


TEST_PUSH_TITLE = "AquaLogic Push Test"
TEST_PUSH_BODY = "Railway → Firebase → Android is working."


@dataclass(frozen=True)
class TestPushReservation:
    event_id: int
    delivery_id: int
    device_id: int
    claim: DeliveryClaim


@dataclass(frozen=True)
class ExistingTestPush:
    event_id: int


def _latest_eligible_admin_device_id(db: Session, *, now: datetime) -> int | None:
    """Select only an active admin's current Android installation with a FID."""
    statement = (
        select(PushDevice.id)
        .join(User, User.id == PushDevice.user_id)
        .join(AuthSession, AuthSession.id == PushDevice.auth_session_id)
        .where(
            PushDevice.is_active.is_(True),
            PushDevice.platform == "android",
            PushDevice.firebase_installation_id.is_not(None),
            PushDevice.firebase_installation_id_registered.is_(True),
            User.is_active.is_(True),
            User.role == "admin",
            AuthSession.user_id == PushDevice.user_id,
            AuthSession.revoked_at.is_(None),
            AuthSession.expires_at > now,
        )
        .order_by(PushDevice.last_registered_at.desc(), PushDevice.id.desc())
        .limit(1)
    )
    if db.bind is not None and db.bind.dialect.name == "postgresql":
        statement = statement.with_for_update(of=PushDevice)
    return db.scalar(statement)


def _reserve_test_push(
    session_factory: Callable[[], Session],
    *,
    request_id: str,
    now: datetime,
) -> TestPushReservation | ExistingTestPush | None:
    event_key = f"test_push:{request_id}"
    existing: PushNotificationEvent | None = None
    try:
        with session_factory() as db:
            existing = db.scalar(
                select(PushNotificationEvent).where(
                    PushNotificationEvent.event_key == event_key
                )
            )
            if existing is not None:
                return ExistingTestPush(event_id=existing.id)

            device_id = _latest_eligible_admin_device_id(db, now=now)
            if device_id is None:
                return None

            claim_token = str(uuid.uuid4())
            event = PushNotificationEvent(
                event_key=event_key,
                event_type="test_push",
                source_type="manual_test",
                source_id=request_id,
                tank_id=None,
                title=TEST_PUSH_TITLE,
                body=TEST_PUSH_BODY,
                payload={
                    "schema_version": "1",
                    "type": "test_push",
                    "event_key": event_key,
                },
            )
            db.add(event)
            db.flush()

            # Reserve the sole target before commit. The production dispatcher
            # cannot claim this row while the CLI performs the Firebase call.
            delivery = PushNotificationDelivery(
                event_id=event.id,
                push_device_id=device_id,
                status="sending",
                attempt_count=1,
                next_attempt_at=now,
                locked_at=now,
                lock_token=claim_token,
            )
            db.add(delivery)
            db.flush()
            reservation = TestPushReservation(
                event_id=event.id,
                delivery_id=delivery.id,
                device_id=device_id,
                claim=DeliveryClaim(
                    delivery_id=delivery.id,
                    lock_token=claim_token,
                ),
            )
            db.commit()
            return reservation
    except IntegrityError:
        # A concurrent invocation with the same request ID is never sent twice.
        with session_factory() as db:
            existing = db.scalar(
                select(PushNotificationEvent).where(
                    PushNotificationEvent.event_key == event_key
                )
            )
        if existing is not None:
            return ExistingTestPush(event_id=existing.id)
        raise


def _delivery_result(
    session_factory: Callable[[], Session], delivery_id: int
) -> tuple[str, str | None, bool]:
    with session_factory() as db:
        delivery = db.get(PushNotificationDelivery, delivery_id)
        if delivery is None:
            return "missing", "delivery_missing", False
        return (
            delivery.status,
            delivery.last_error_code,
            delivery.firebase_message_id is not None,
        )


def main(
    argv: Sequence[str] | None = None,
    *,
    session_factory: Callable[[], Session] | None = None,
    sender: PushSender | None = None,
    push_enabled: bool | None = None,
    stdout: Callable[[str], None] = print,
    stderr: Callable[[str], None] = print,
) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Send one controlled test push to the latest eligible admin Android "
            "installation with a registered Firebase Installation ID."
        )
    )
    parser.add_argument(
        "--request-id",
        required=True,
        help="A UUID idempotency key; reuse it if the command's result is uncertain.",
    )
    parser.add_argument(
        "--confirm",
        action="store_true",
        help="Required to enqueue and send exactly one test notification.",
    )
    args = parser.parse_args(argv)

    try:
        request_id = str(uuid.UUID(args.request_id))
    except (AttributeError, TypeError, ValueError):
        stderr("--request-id must be a UUID; no notification was sent")
        return 2

    if not args.confirm:
        stderr("No notification sent; pass --confirm to authorize one test push")
        return 2

    enabled = settings.push_notifications_enabled if push_enabled is None else push_enabled
    if not enabled:
        stderr("PUSH_NOTIFICATIONS_ENABLED is false; no notification was queued")
        return 2

    factory = SessionLocal if session_factory is None else session_factory
    now = utc_now()
    try:
        reservation = _reserve_test_push(factory, request_id=request_id, now=now)
    except Exception:
        stderr("Could not reserve the test notification; no sensitive values were logged")
        return 1

    if reservation is None:
        stderr(
            "No eligible active admin Android installation with a registered FID; "
            "no notification was queued"
        )
        return 1
    if isinstance(reservation, ExistingTestPush):
        stderr(
            "This request ID already has an outbox event; no second notification was sent "
            f"(event_id={reservation.event_id})"
        )
        return 2

    selected_sender = sender if sender is not None else FirebaseAdminPushSender()
    try:
        _dispatch_claim(factory, selected_sender, reservation.claim, now=now)
        status_value, error_code, message_id_stored = _delivery_result(
            factory, reservation.delivery_id
        )
    except Exception:
        stderr(
            "Test dispatch did not complete; inspect sanitized delivery status before retrying "
            f"(event_id={reservation.event_id}, delivery_id={reservation.delivery_id})"
        )
        return 1

    if status_value == "sent":
        stdout(
            "Test push sent to one eligible admin Android installation "
            f"(event_id={reservation.event_id}, delivery_id={reservation.delivery_id}, "
            f"device_id={reservation.device_id}, firebase_message_id_stored={message_id_stored})"
        )
        return 0

    stderr(
        "Test push was not marked sent "
        f"(event_id={reservation.event_id}, delivery_id={reservation.delivery_id}, "
        f"status={status_value}, error_code={error_code or 'none'})"
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

"""Send one M6.6 notification to an existing operational record.

This guarded operator command never creates or edits an Alert or
MonitoringIncident. It selects an existing suitable record and one currently
eligible Android installation with a registered Firebase Installation ID.
The normal event-key uniqueness rule prevents sending the same record test
twice or backfilling a previously-created event.
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
    Alert,
    AuthSession,
    MonitoringIncident,
    PushDevice,
    PushNotificationDelivery,
    PushNotificationEvent,
    Tank,
    User,
)
from app.security import utc_now
from app.services.push_notifications import DeliveryClaim, _dispatch_claim
from app.services.push_sender import FirebaseAdminPushSender, PushSender


@dataclass(frozen=True)
class _Kind:
    event_type: str
    payload_id_key: str
    event_key_prefix: str
    event_key_suffix: str
    title: str
    body: str


_KINDS = {
    "alert": _Kind(
        event_type="water_quality_alert",
        payload_id_key="alert_id",
        event_key_prefix="water_quality_alert",
        event_key_suffix="created",
        title="AquaLogic M6.6 alert check",
        body="Open AquaLogic to view the current alert.",
    ),
    "monitoring": _Kind(
        event_type="monitoring_incident",
        payload_id_key="incident_id",
        event_key_prefix="monitoring_incident",
        event_key_suffix="opened",
        title="AquaLogic M6.6 monitoring check",
        body="Open AquaLogic to view current monitoring status.",
    ),
    "recovery": _Kind(
        event_type="monitoring_recovered",
        payload_id_key="incident_id",
        event_key_prefix="monitoring_incident",
        event_key_suffix="recovered",
        title="AquaLogic M6.6 recovery check",
        body="Open AquaLogic to view recovery history.",
    ),
}


@dataclass(frozen=True)
class _Reservation:
    delivery_id: int
    claim: DeliveryClaim


def _existing_record_id_and_tank_id(
    db: Session, *, kind: str
) -> tuple[int, int] | None:
    if kind == "alert":
        statement = (
            select(Alert.id, Alert.tank_id)
            .join(Tank, Tank.id == Alert.tank_id)
            .where(Tank.retired_at.is_(None))
            .order_by(Alert.is_resolved.asc(), Alert.created_at.desc(), Alert.id.desc())
        )
    elif kind == "monitoring":
        statement = (
            select(MonitoringIncident.id, MonitoringIncident.tank_id)
            .join(Tank, Tank.id == MonitoringIncident.tank_id)
            .where(
                Tank.retired_at.is_(None),
                MonitoringIncident.resolved_at.is_(None),
            )
            .order_by(
                MonitoringIncident.started_at.desc(),
                MonitoringIncident.id.desc(),
            )
        )
    elif kind == "recovery":
        statement = (
            select(MonitoringIncident.id, MonitoringIncident.tank_id)
            .join(Tank, Tank.id == MonitoringIncident.tank_id)
            .where(
                Tank.retired_at.is_(None),
                MonitoringIncident.resolved_at.is_not(None),
                MonitoringIncident.resolution_reason == "reporting_recovered",
            )
            .order_by(
                MonitoringIncident.resolved_at.desc(),
                MonitoringIncident.id.desc(),
            )
        )
    else:
        raise ValueError("Unsupported M6.6 test kind")

    row = db.execute(statement.limit(1)).first()
    return (int(row[0]), int(row[1])) if row is not None else None


def _latest_eligible_device_id(db: Session, *, now: datetime) -> int | None:
    """Select one current session-bound Android recipient without loading its FID."""
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
            User.role.in_(("admin", "staff")),
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


def _reserve_test_notification(
    session_factory: Callable[[], Session], *, kind: str, now: datetime
) -> tuple[str, _Reservation | None]:
    spec = _KINDS[kind]
    try:
        with session_factory() as db:
            source = _existing_record_id_and_tank_id(db, kind=kind)
            if source is None:
                return "no_existing_record", None
            source_id, tank_id = source
            source_id_text = str(source_id)
            event_key = (
                f"{spec.event_key_prefix}:{source_id_text}:{spec.event_key_suffix}"
            )
            existing = db.scalar(
                select(PushNotificationEvent.id).where(
                    PushNotificationEvent.event_key == event_key
                )
            )
            if existing is not None:
                return "already_enqueued", None

            device_id = _latest_eligible_device_id(db, now=now)
            if device_id is None:
                return "no_eligible_device", None

            claim_token = str(uuid.uuid4())
            event = PushNotificationEvent(
                event_key=event_key,
                event_type=spec.event_type,
                source_type="manual_test",
                source_id=source_id_text,
                tank_id=tank_id,
                title=spec.title,
                body=spec.body,
                payload={
                    "schema_version": "1",
                    "type": spec.event_type,
                    "event_key": event_key,
                    "tank_id": str(tank_id),
                    spec.payload_id_key: source_id_text,
                },
            )
            with db.begin_nested():
                db.add(event)
                db.flush()
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
                reservation = _Reservation(
                    delivery_id=delivery.id,
                    claim=DeliveryClaim(
                        delivery_id=delivery.id,
                        lock_token=claim_token,
                    ),
                )
            db.commit()
            return "reserved", reservation
    except IntegrityError:
        with session_factory() as db:
            source = _existing_record_id_and_tank_id(db, kind=kind)
            if source is None:
                return "no_existing_record", None
            source_id = str(source[0])
            event_key = (
                f"{spec.event_key_prefix}:{source_id}:{spec.event_key_suffix}"
            )
            exists = db.scalar(
                select(PushNotificationEvent.id).where(
                    PushNotificationEvent.event_key == event_key
                )
            )
        if exists is not None:
            return "already_enqueued", None
        raise


def _delivery_status(
    session_factory: Callable[[], Session], delivery_id: int
) -> tuple[str, str | None]:
    with session_factory() as db:
        delivery = db.get(PushNotificationDelivery, delivery_id)
        if delivery is None:
            return "missing", "delivery_missing"
        return delivery.status, delivery.last_error_code


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
            "Send one M6.6 navigation check to an existing Alert or monitoring "
            "record and one eligible Android installation."
        )
    )
    parser.add_argument("--kind", required=True, choices=tuple(_KINDS))
    parser.add_argument(
        "--confirm",
        action="store_true",
        help="Required to enqueue and send one test notification.",
    )
    args = parser.parse_args(argv)

    if not args.confirm:
        stderr("No notification sent; pass --confirm to authorize one M6.6 test push")
        return 2

    enabled = settings.push_notifications_enabled if push_enabled is None else push_enabled
    if not enabled:
        stderr("PUSH_NOTIFICATIONS_ENABLED is false; no notification was queued")
        return 2

    factory = SessionLocal if session_factory is None else session_factory
    try:
        outcome, reservation = _reserve_test_notification(
            factory, kind=args.kind, now=utc_now()
        )
    except Exception:
        stderr("Could not reserve the test notification; no sensitive values were logged")
        return 1

    if outcome == "no_existing_record":
        stderr(f"No suitable existing {args.kind} record; no notification was queued")
        return 1
    if outcome == "already_enqueued":
        stderr("This record already has its deterministic event; no repeat was sent")
        return 2
    if outcome == "no_eligible_device" or reservation is None:
        stderr(
            "No eligible session-bound Android installation with a registered FID; "
            "no notification was queued"
        )
        return 1

    selected_sender = sender if sender is not None else FirebaseAdminPushSender()
    try:
        _dispatch_claim(factory, selected_sender, reservation.claim, now=utc_now())
        status, error_code = _delivery_status(factory, reservation.delivery_id)
    except Exception:
        stderr("Test dispatch did not complete; inspect sanitized delivery status")
        return 1

    if status == "sent":
        stdout(
            f"M6.6 {args.kind} test notification sent to one eligible Android "
            "installation"
        )
        return 0

    stderr(
        f"M6.6 {args.kind} test delivery was not marked sent "
        f"(status={status}, error_code={error_code or 'none'})"
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

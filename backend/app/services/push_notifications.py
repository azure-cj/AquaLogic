"""Transactional push outbox and independent leased dispatcher."""

import logging
import threading
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Callable

from sqlalchemy import and_, case, or_, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.config import settings
from app.database import SessionLocal
from app.models import PushDevice, PushNotificationDelivery, PushNotificationEvent
from app.security import utc_now
from app.services.push_devices import eligible_push_device, eligible_push_device_ids
from app.services.push_sender import (
    FirebaseAdminPushSender,
    PushConfigurationError,
    PushPermanentRecipientError,
    PushSender,
    PushTransientError,
)


logger = logging.getLogger(__name__)

MAX_DELIVERY_ATTEMPTS = 5
DELIVERY_LEASE_SECONDS = 180
DISPATCH_BATCH_SIZE = 20
RETRY_BASE_SECONDS = 30
RETRY_MAX_SECONDS = 3600
CONFIGURATION_RECHECK_SECONDS = 60

_EVENT_CONTRACTS = {
    "water_quality_alert": ("alert", "alert_id", "water_quality_alert", "created"),
    "monitoring_incident": (
        "monitoring_incident",
        "incident_id",
        "monitoring_incident",
        "opened",
    ),
    "monitoring_recovered": (
        "monitoring_incident",
        "incident_id",
        "monitoring_incident",
        "recovered",
    ),
}


@dataclass(frozen=True)
class DeliveryClaim:
    delivery_id: int
    lock_token: str


def enqueue_push_notification(
    db: Session,
    *,
    event_type: str,
    source_id: int | str,
    tank_id: int,
    title: str,
    body: str,
    now: datetime | None = None,
) -> tuple[PushNotificationEvent | None, bool]:
    """Create one event and its currently eligible deliveries in the caller's transaction.

    The return flag is true only for the transaction that inserted the event.
    The caller owns commit/rollback so M6.5 can pair enqueueing with its source
    Alert or MonitoringIncident transition.
    """
    contract = _EVENT_CONTRACTS.get(event_type)
    if contract is None:
        raise ValueError("Unsupported push event type")
    if not isinstance(tank_id, int) or tank_id < 1:
        raise ValueError("A positive tank ID is required")
    if not isinstance(title, str) or not title.strip() or len(title) > 160:
        raise ValueError("Notification title is invalid")
    if not isinstance(body, str) or not body.strip() or len(body) > 300:
        raise ValueError("Notification body is invalid")

    source_type, payload_id_key, key_prefix, suffix = contract
    normalized_source_id = str(source_id)
    if not normalized_source_id or len(normalized_source_id) > 80:
        raise ValueError("Notification source ID is invalid")
    event_key = f"{key_prefix}:{normalized_source_id}:{suffix}"
    if len(event_key) > 200:
        raise ValueError("Notification event key is invalid")
    data = {
        "schema_version": "1",
        "type": event_type,
        "event_key": event_key,
        "tank_id": str(tank_id),
        payload_id_key: normalized_source_id,
    }
    current_time = now or utc_now()

    existing = db.scalar(
        select(PushNotificationEvent).where(PushNotificationEvent.event_key == event_key)
    )
    if existing is not None:
        return existing, False

    try:
        # Event and recipients must either materialize together or be discarded
        # together, without rolling back the caller's operational transaction.
        with db.begin_nested():
            event = PushNotificationEvent(
                event_key=event_key,
                event_type=event_type,
                source_type=source_type,
                source_id=normalized_source_id,
                tank_id=tank_id,
                title=title.strip(),
                body=body.strip(),
                payload=data,
            )
            db.add(event)
            db.flush()
            for device_id in eligible_push_device_ids(db, now=current_time):
                db.add(
                    PushNotificationDelivery(
                        event_id=event.id,
                        push_device_id=device_id,
                        status="pending",
                        attempt_count=0,
                        next_attempt_at=current_time,
                    )
                )
            db.flush()
    except IntegrityError:
        existing = db.scalar(
            select(PushNotificationEvent).where(PushNotificationEvent.event_key == event_key)
        )
        if existing is not None:
            return existing, False
        logger.warning("Push outbox enqueue skipped after an integrity conflict (code=%s)", "outbox_integrity_error")
        return None, False
    return event, True


def _claimable_condition(now: datetime, lease_seconds: int):
    lease_cutoff = now - timedelta(seconds=lease_seconds)
    return or_(
        and_(
            PushNotificationDelivery.status.in_(("pending", "retry")),
            PushNotificationDelivery.next_attempt_at <= now,
            PushNotificationDelivery.attempt_count < MAX_DELIVERY_ATTEMPTS,
        ),
        and_(
            PushNotificationDelivery.status == "sending",
            PushNotificationDelivery.locked_at <= lease_cutoff,
            PushNotificationDelivery.attempt_count < MAX_DELIVERY_ATTEMPTS,
        ),
    )


def claim_due_deliveries(
    session_factory: Callable[[], Session] = SessionLocal,
    *,
    now: datetime | None = None,
    limit: int = DISPATCH_BATCH_SIZE,
    lease_seconds: int = DELIVERY_LEASE_SECONDS,
) -> list[DeliveryClaim]:
    """Atomically lease due rows; network operations happen after this commits."""
    current_time = now or utc_now()
    lease_cutoff = current_time - timedelta(seconds=lease_seconds)
    claims: list[DeliveryClaim] = []

    with session_factory() as db:
        stale_exhausted = db.execute(
            update(PushNotificationDelivery)
            .where(
                PushNotificationDelivery.status == "sending",
                PushNotificationDelivery.locked_at <= lease_cutoff,
                PushNotificationDelivery.attempt_count >= MAX_DELIVERY_ATTEMPTS,
            )
            .values(
                status="permanent_failed",
                last_error_code="attempts_exhausted",
                locked_at=None,
                lock_token=None,
                updated_at=current_time,
            )
        )

        statement = (
            select(PushNotificationDelivery.id)
            .where(_claimable_condition(current_time, lease_seconds))
            .order_by(PushNotificationDelivery.id)
            .limit(limit)
        )
        if db.bind is not None and db.bind.dialect.name == "postgresql":
            statement = statement.with_for_update(skip_locked=True)
        candidate_ids = list(db.scalars(statement).all())

        condition = _claimable_condition(current_time, lease_seconds)
        for delivery_id in candidate_ids:
            token = str(uuid.uuid4())
            result = db.execute(
                update(PushNotificationDelivery)
                .where(PushNotificationDelivery.id == delivery_id, condition)
                .values(
                    status="sending",
                    attempt_count=PushNotificationDelivery.attempt_count + 1,
                    locked_at=current_time,
                    lock_token=token,
                    updated_at=current_time,
                )
            )
            if result.rowcount == 1:
                claims.append(DeliveryClaim(delivery_id=delivery_id, lock_token=token))

        if stale_exhausted.rowcount or claims:
            db.commit()
        else:
            db.rollback()
    return claims


def _owned_delivery_update(
    db: Session, claim: DeliveryClaim, *, values: dict
) -> int:
    result = db.execute(
        update(PushNotificationDelivery)
        .where(
            PushNotificationDelivery.id == claim.delivery_id,
            PushNotificationDelivery.status == "sending",
            PushNotificationDelivery.lock_token == claim.lock_token,
        )
        .values(**values)
    )
    return result.rowcount or 0


def _mark_ineligible(
    session_factory: Callable[[], Session], claim: DeliveryClaim, *, now: datetime
) -> None:
    with session_factory() as db:
        changed = _owned_delivery_update(
            db,
            claim,
            values={
                "status": "skipped",
                "attempt_count": case(
                    (PushNotificationDelivery.attempt_count > 0, PushNotificationDelivery.attempt_count - 1),
                    else_=0,
                ),
                "last_error_code": "recipient_ineligible",
                "locked_at": None,
                "lock_token": None,
                "updated_at": now,
            },
        )
        if changed:
            db.commit()
        else:
            db.rollback()


def _schedule_retry(
    session_factory: Callable[[], Session],
    claim: DeliveryClaim,
    *,
    now: datetime,
    error_code: str,
    attempt_count: int,
) -> None:
    exhausted = attempt_count >= MAX_DELIVERY_ATTEMPTS
    delay = min(RETRY_BASE_SECONDS * (2 ** max(0, attempt_count - 1)), RETRY_MAX_SECONDS)
    with session_factory() as db:
        changed = _owned_delivery_update(
            db,
            claim,
            values={
                "status": "permanent_failed" if exhausted else "retry",
                "next_attempt_at": now + timedelta(seconds=delay),
                "last_error_code": "attempts_exhausted" if exhausted else error_code,
                "locked_at": None,
                "lock_token": None,
                "updated_at": now,
            },
        )
        if changed:
            db.commit()
        else:
            db.rollback()


def _release_configuration_failure(
    session_factory: Callable[[], Session], claim: DeliveryClaim, *, now: datetime
) -> None:
    """Leave events retryable until global Firebase configuration is fixed."""
    with session_factory() as db:
        changed = _owned_delivery_update(
            db,
            claim,
            values={
                "status": "pending",
                "attempt_count": case(
                    (PushNotificationDelivery.attempt_count > 0, PushNotificationDelivery.attempt_count - 1),
                    else_=0,
                ),
                "next_attempt_at": now + timedelta(seconds=CONFIGURATION_RECHECK_SECONDS),
                "last_error_code": PushConfigurationError.error_code,
                "locked_at": None,
                "lock_token": None,
                "updated_at": now,
            },
        )
        if changed:
            db.commit()
        else:
            db.rollback()


def _load_claimed_work(
    db: Session, claim: DeliveryClaim
) -> tuple[PushNotificationDelivery, PushNotificationEvent] | None:
    row = db.execute(
        select(PushNotificationDelivery, PushNotificationEvent)
        .join(
            PushNotificationEvent,
            PushNotificationEvent.id == PushNotificationDelivery.event_id,
        )
        .where(
            PushNotificationDelivery.id == claim.delivery_id,
            PushNotificationDelivery.status == "sending",
            PushNotificationDelivery.lock_token == claim.lock_token,
        )
    ).first()
    if row is None:
        return None
    return row[0], row[1]


def _dispatch_claim(
    session_factory: Callable[[], Session],
    sender: PushSender,
    claim: DeliveryClaim,
    *,
    now: datetime,
) -> bool:
    with session_factory() as db:
        work = _load_claimed_work(db, claim)
        if work is None:
            return False
        delivery, event = work
        attempt_count = delivery.attempt_count
        device_id = delivery.push_device_id
        title = event.title
        body = event.body
        data = dict(event.payload)
        device = eligible_push_device(db, device_id, now=now)
        firebase_installation_id = (
            device.firebase_installation_id
            if device is not None
            and device.firebase_installation_id_registered
            else None
        )
        fcm_token = (
            device.fcm_token
            if device is not None and firebase_installation_id is None
            else None
        )

    if device is None or (firebase_installation_id is None and fcm_token is None):
        _mark_ineligible(session_factory, claim, now=now)
        return False

    try:
        firebase_message_id = sender.send(
            firebase_installation_id=firebase_installation_id,
            fcm_token=fcm_token,
            title=title,
            body=body,
            data=data,
        )
    except PushConfigurationError:
        _release_configuration_failure(session_factory, claim, now=now)
        return True
    except PushPermanentRecipientError as exc:
        with session_factory() as db:
            # A late error must not disable a device whose recipient changed.
            recipient_column = (
                PushDevice.firebase_installation_id
                if firebase_installation_id is not None
                else PushDevice.fcm_token
            )
            recipient = firebase_installation_id or fcm_token
            recipient_filter = (
                PushDevice.firebase_installation_id_registered.is_(True)
                if firebase_installation_id is not None
                else PushDevice.firebase_installation_id_registered.is_(False)
            )
            db.execute(
                update(PushDevice)
                .where(
                    PushDevice.id == device_id,
                    recipient_column == recipient,
                    recipient_filter,
                    PushDevice.is_active.is_(True),
                )
                .values(is_active=False, disabled_at=now, updated_at=now)
            )
            _owned_delivery_update(
                db,
                claim,
                values={
                    "status": "permanent_failed",
                    "last_error_code": exc.error_code,
                    "locked_at": None,
                    "lock_token": None,
                    "updated_at": now,
                },
            )
            # Keep a valid recipient deactivation even if this lease was replaced
            # while the network request was in flight.
            db.commit()
        return False
    except PushTransientError as exc:
        _schedule_retry(
            session_factory,
            claim,
            now=now,
            error_code=exc.error_code,
            attempt_count=attempt_count,
        )
        logger.warning("Push delivery attempt failed (code=%s)", exc.error_code)
        return False
    except Exception:
        # Unknown SDK/fake failures are sanitized and bounded as transient.
        _schedule_retry(
            session_factory,
            claim,
            now=now,
            error_code=PushTransientError.error_code,
            attempt_count=attempt_count,
        )
        logger.warning("Push delivery attempt failed (code=%s)", PushTransientError.error_code)
        return False
    else:
        with session_factory() as db:
            changed = _owned_delivery_update(
                db,
                claim,
                values={
                    "status": "sent",
                    "firebase_message_id": firebase_message_id,
                    "last_error_code": None,
                    "locked_at": None,
                    "lock_token": None,
                    "sent_at": now,
                    "updated_at": now,
                },
            )
            if changed:
                db.commit()
            else:
                db.rollback()
        return False


class PushDispatcher:
    """Independent daemon loop for push delivery, separate from maintenance."""

    def __init__(
        self,
        *,
        enabled: bool,
        interval_seconds: int,
        session_factory: Callable[[], Session] = SessionLocal,
        sender: PushSender | None = None,
    ) -> None:
        self.enabled = enabled
        self.interval_seconds = interval_seconds
        self.session_factory = session_factory
        self.sender = sender or (FirebaseAdminPushSender() if enabled else None)
        self.configuration_blocked = False
        self.stop_event = threading.Event()
        self.thread: threading.Thread | None = None

    def run_once(self, *, now: datetime | None = None) -> int:
        if not self.enabled or self.sender is None or self.configuration_blocked:
            return 0
        current_time = now or utc_now()
        claims = claim_due_deliveries(self.session_factory, now=current_time)
        for index, claim in enumerate(claims):
            try:
                configuration_error = _dispatch_claim(
                    self.session_factory, self.sender, claim, now=current_time
                )
                if configuration_error:
                    self.configuration_blocked = True
                    for remaining_claim in claims[index + 1 :]:
                        _release_configuration_failure(
                            self.session_factory,
                            remaining_claim,
                            now=current_time,
                        )
                    logger.error(
                        "Push dispatcher paused by Firebase configuration (code=%s)",
                        PushConfigurationError.error_code,
                    )
                    break
            except Exception:
                # Database or unexpected infrastructure failures stay local to
                # this iteration and are logged without exception details.
                logger.error("Push dispatcher could not complete a claimed delivery (code=%s)", "dispatcher_error")
        return len(claims)

    def start(self) -> "PushDispatcher":
        if not self.enabled or self.thread is not None:
            return self

        if isinstance(self.sender, FirebaseAdminPushSender):
            try:
                self.sender.validate_configuration()
            except PushConfigurationError:
                self.configuration_blocked = True
                logger.error(
                    "Push dispatcher paused by Firebase configuration (code=%s)",
                    PushConfigurationError.error_code,
                )
            except Exception:
                self.configuration_blocked = True
                logger.error(
                    "Push dispatcher paused during Firebase setup (code=%s)",
                    "firebase_setup_error",
                )

        def _loop() -> None:
            while not self.stop_event.is_set():
                try:
                    self.run_once()
                except Exception:
                    logger.error("Push dispatcher cycle failed (code=%s)", "dispatcher_error")
                self.stop_event.wait(self.interval_seconds)

        self.thread = threading.Thread(target=_loop, name="aqualogic-push-dispatcher", daemon=True)
        self.thread.start()
        return self

    def stop(self) -> None:
        self.stop_event.set()
        if self.thread is not None:
            self.thread.join(timeout=max(5, min(30, self.interval_seconds + 2)))


def start_push_dispatcher() -> PushDispatcher | None:
    """Start push delivery only when explicitly enabled by configuration."""
    if not settings.push_notifications_enabled:
        return None
    return PushDispatcher(
        enabled=True,
        interval_seconds=settings.push_dispatch_interval_seconds,
    ).start()

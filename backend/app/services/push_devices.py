from datetime import datetime

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import AuthSession, PushDevice, User
from app.security import utc_now


def eligible_push_devices(db: Session, *, now: datetime | None = None) -> list[PushDevice]:
    """Select active Android registrations bound to a live AquaLogic session."""
    current_time = now or utc_now()
    return list(
        db.scalars(
            select(PushDevice)
            .join(User, User.id == PushDevice.user_id)
            .join(AuthSession, AuthSession.id == PushDevice.auth_session_id)
            .where(
                PushDevice.is_active.is_(True),
                PushDevice.platform == "android",
                User.is_active.is_(True),
                User.role.in_(("admin", "staff")),
                AuthSession.user_id == PushDevice.user_id,
                AuthSession.revoked_at.is_(None),
                AuthSession.expires_at > current_time,
            )
            .order_by(PushDevice.id)
        ).all()
    )


def eligible_push_device_ids(db: Session, *, now: datetime | None = None) -> list[int]:
    """Select eligible IDs without loading stored FCM tokens."""
    current_time = now or utc_now()
    return list(
        db.scalars(
            select(PushDevice.id)
            .join(User, User.id == PushDevice.user_id)
            .join(AuthSession, AuthSession.id == PushDevice.auth_session_id)
            .where(
                PushDevice.is_active.is_(True),
                PushDevice.platform == "android",
                User.is_active.is_(True),
                User.role.in_(("admin", "staff")),
                AuthSession.user_id == PushDevice.user_id,
                AuthSession.revoked_at.is_(None),
                AuthSession.expires_at > current_time,
            )
            .order_by(PushDevice.id)
        ).all()
    )


def eligible_push_device(
    db: Session, device_id: int, *, now: datetime | None = None
) -> PushDevice | None:
    """Recheck current account, role, device, and session eligibility."""
    current_time = now or utc_now()
    return db.scalar(
        select(PushDevice)
        .join(User, User.id == PushDevice.user_id)
        .join(AuthSession, AuthSession.id == PushDevice.auth_session_id)
        .where(
            PushDevice.id == device_id,
            PushDevice.is_active.is_(True),
            PushDevice.platform == "android",
            User.is_active.is_(True),
            User.role.in_(("admin", "staff")),
            AuthSession.user_id == PushDevice.user_id,
            AuthSession.revoked_at.is_(None),
            AuthSession.expires_at > current_time,
        )
    )

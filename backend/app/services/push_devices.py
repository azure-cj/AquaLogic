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

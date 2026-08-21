from datetime import datetime

from fastapi import APIRouter, Depends, Query
from sqlalchemy import and_, or_, select
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import require_admin
from app.models import SecurityAuditEvent, User
from app.schemas.auth import SecurityAuditEventRead


router = APIRouter(prefix="/security", tags=["security"])


@router.get("/audit-events", response_model=list[SecurityAuditEventRead])
def list_audit_events(
    user_id: int | None = None,
    event_type: str | None = None,
    outcome: str | None = None,
    since: datetime | None = None,
    until: datetime | None = None,
    before_id: int | None = None,
    limit: int = Query(default=50, ge=1, le=100),
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
) -> list[SecurityAuditEvent]:
    statement = select(SecurityAuditEvent)
    if user_id is not None:
        statement = statement.where(
            or_(
                SecurityAuditEvent.actor_user_id == user_id,
                and_(
                    SecurityAuditEvent.target_type == "user",
                    SecurityAuditEvent.target_id == str(user_id),
                ),
            )
        )
    if event_type:
        statement = statement.where(SecurityAuditEvent.event_type == event_type)
    if outcome:
        statement = statement.where(SecurityAuditEvent.outcome == outcome)
    if since is not None:
        statement = statement.where(SecurityAuditEvent.created_at >= since)
    if until is not None:
        statement = statement.where(SecurityAuditEvent.created_at <= until)
    if before_id is not None:
        statement = statement.where(SecurityAuditEvent.id < before_id)
    return list(db.scalars(statement.order_by(SecurityAuditEvent.id.desc()).limit(limit)).all())

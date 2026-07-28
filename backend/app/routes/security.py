from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import require_admin
from app.models import SecurityAuditEvent, User
from app.schemas.auth import SecurityAuditEventRead


router = APIRouter(prefix="/security", tags=["security"])


@router.get("/audit-events", response_model=list[SecurityAuditEventRead])
def list_audit_events(
    before_id: int | None = None,
    limit: int = Query(default=50, ge=1, le=100),
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
) -> list[SecurityAuditEvent]:
    statement = select(SecurityAuditEvent)
    if before_id is not None:
        statement = statement.where(SecurityAuditEvent.id < before_id)
    return list(db.scalars(statement.order_by(SecurityAuditEvent.id.desc()).limit(limit)).all())

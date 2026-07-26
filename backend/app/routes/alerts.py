from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import require_password_change_complete
from app.models import Alert, User
from app.schemas.alert import AlertRead

router = APIRouter(tags=["alerts"])


def _get_alert_or_404(db: Session, alert_id: int) -> Alert:
    alert = db.scalar(select(Alert).where(Alert.id == alert_id))
    if alert is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Alert not found")
    return alert


@router.get("/alerts", response_model=list[AlertRead])
def list_alerts(
    include_resolved: bool = False,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_password_change_complete),
) -> list[Alert]:
    _ = current_user
    stmt = select(Alert)
    if not include_resolved:
        stmt = stmt.where(Alert.is_resolved.is_(False))
    alerts = db.scalars(stmt.order_by(Alert.created_at.desc())).all()
    return list(alerts)


@router.get("/tanks/{tank_id}/alerts", response_model=list[AlertRead])
def list_tank_alerts(
    tank_id: int,
    include_resolved: bool = False,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_password_change_complete),
) -> list[Alert]:
    _ = current_user
    stmt = select(Alert).where(Alert.tank_id == tank_id)
    if not include_resolved:
        stmt = stmt.where(Alert.is_resolved.is_(False))
    alerts = db.scalars(stmt.order_by(Alert.created_at.desc())).all()
    return list(alerts)


@router.put("/alerts/{alert_id}/resolve", response_model=AlertRead)
def resolve_alert(
    alert_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_password_change_complete),
) -> Alert:
    alert = _get_alert_or_404(db, alert_id)
    if not alert.is_resolved:
        alert.is_resolved = True
        alert.resolved_at = datetime.now(timezone.utc)
        alert.resolved_by_user_id = current_user.id
        db.commit()
        db.refresh(alert)
    return alert


@router.get("/alerts/history", response_model=list[AlertRead])
def alert_history(
    tank_id: int | None = None,
    severity: str | None = None,
    parameter: str | None = None,
    resolved: bool | None = None,
    created_after: datetime | None = None,
    created_before: datetime | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_password_change_complete),
) -> list[Alert]:
    _ = current_user
    stmt = select(Alert)
    if tank_id is not None: stmt = stmt.where(Alert.tank_id == tank_id)
    if severity is not None: stmt = stmt.where(Alert.severity == severity)
    if parameter is not None: stmt = stmt.where(Alert.parameter == parameter)
    if resolved is not None: stmt = stmt.where(Alert.is_resolved.is_(resolved))
    if created_after is not None: stmt = stmt.where(Alert.created_at >= created_after)
    if created_before is not None: stmt = stmt.where(Alert.created_at <= created_before)
    return list(db.scalars(stmt.order_by(Alert.created_at.desc())).all())

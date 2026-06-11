from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user
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
    current_user: User = Depends(get_current_user),
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
    current_user: User = Depends(get_current_user),
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
    current_user: User = Depends(get_current_user),
) -> Alert:
    _ = current_user
    alert = _get_alert_or_404(db, alert_id)
    if not alert.is_resolved:
        alert.is_resolved = True
        db.commit()
        db.refresh(alert)
    return alert

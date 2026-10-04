from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import require_staff
from app.models import Alert, Tank, User
from app.schemas.alert import AlertContextRead, AlertHistoryPage, AlertRead
from app.services.alert_context import build_alert_context
from app.services.auth_security import audit_event
from app.services.tank_lifecycle import require_active_tank, tank_or_404

router = APIRouter(tags=["alerts"])


def _get_alert_or_404(db: Session, alert_id: int) -> Alert:
    alert = db.scalar(select(Alert).where(Alert.id == alert_id))
    if alert is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Alert not found")
    return alert


@router.get("/alerts/{alert_id}/context", response_model=AlertContextRead)
def alert_context(
    alert_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_staff),
) -> dict:
    return build_alert_context(db, _get_alert_or_404(db, alert_id))


@router.get("/alerts", response_model=list[AlertRead])
def list_alerts(
    include_resolved: bool = False,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_staff),
) -> list[Alert]:
    _ = current_user
    stmt = select(Alert).join(Tank, Tank.id == Alert.tank_id).where(Tank.retired_at.is_(None))
    if not include_resolved:
        stmt = stmt.where(Alert.is_resolved.is_(False))
    alerts = db.scalars(stmt.order_by(Alert.created_at.desc())).all()
    return list(alerts)


@router.get("/tanks/{tank_id}/alerts", response_model=list[AlertRead])
def list_tank_alerts(
    tank_id: int,
    include_resolved: bool = False,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_staff),
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
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_staff),
) -> Alert:
    alert = _get_alert_or_404(db, alert_id)
    require_active_tank(tank_or_404(db, alert.tank_id))
    if not alert.is_resolved:
        alert.is_resolved = True
        alert.resolved_at = datetime.now(timezone.utc)
        alert.resolved_by_user_id = current_user.id
        alert.resolution_source = "operator"
        audit_event(db, request, "alert.resolve", "success", actor_user_id=current_user.id, target_type="alert", target_id=alert.id)
        db.commit()
        db.refresh(alert)
    return alert


@router.get("/alerts/history", response_model=AlertHistoryPage | list[AlertRead])
def alert_history(
    tank_id: int | None = None,
    severity: str | None = None,
    parameter: str | None = None,
    parameters: list[str] | None = Query(default=None),
    resolved: bool | None = None,
    created_after: datetime | None = None,
    created_before: datetime | None = None,
    page: int | None = Query(default=None, ge=1),
    page_size: int | None = Query(default=None, ge=1, le=100),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_staff),
) -> AlertHistoryPage | list[Alert]:
    _ = current_user
    stmt = select(Alert)
    if tank_id is not None: stmt = stmt.where(Alert.tank_id == tank_id)
    if severity is not None: stmt = stmt.where(Alert.severity == severity)
    if parameter is not None: stmt = stmt.where(Alert.parameter == parameter)
    if parameters is not None: stmt = stmt.where(Alert.parameter.in_(parameters))
    if resolved is not None: stmt = stmt.where(Alert.is_resolved.is_(resolved))
    if created_after is not None: stmt = stmt.where(Alert.created_at >= created_after)
    if created_before is not None: stmt = stmt.where(Alert.created_at <= created_before)

    ordered_statement = stmt.order_by(Alert.created_at.desc(), Alert.id.desc())
    if page is None and page_size is None:
        return list(db.scalars(ordered_statement).all())

    page = page or 1
    page_size = page_size or 25
    total = int(db.scalar(select(func.count()).select_from(stmt.order_by(None).subquery())) or 0)
    items = list(
        db.scalars(
            ordered_statement
            .offset((page - 1) * page_size)
            .limit(page_size)
        ).all()
    )
    total_pages = (total + page_size - 1) // page_size
    return AlertHistoryPage(
        items=items,
        page=page,
        page_size=page_size,
        total=total,
        total_pages=total_pages,
        has_previous=page > 1,
        has_next=page < total_pages,
    )

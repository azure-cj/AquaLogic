from datetime import datetime, timezone
from typing import Literal

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session, selectinload

from app.database import get_db
from app.dependencies import require_staff
from app.models import MonitoringIncident, Tank, User
from app.schemas.monitoring import MonitoringIncidentPage, MonitoringIncidentRead
from app.services.tank_lifecycle import tank_or_404


router = APIRouter(tags=["monitoring incidents"])


def _utc(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


def _incident_read(incident: MonitoringIncident, now: datetime) -> MonitoringIncidentRead:
    started_at = _utc(incident.started_at)
    resolved_at = _utc(incident.resolved_at)
    last_report = _utc(incident.last_reading_received_at)
    assert started_at is not None
    end = resolved_at or now
    return MonitoringIncidentRead(
        id=incident.id,
        tank_id=incident.tank_id,
        tank_name=incident.tank.name,
        tank_lifecycle=incident.tank.lifecycle,
        state="resolved" if resolved_at is not None else "active",
        started_at=started_at,
        detected_at=_utc(incident.detected_at),
        last_reading_received_at=last_report,
        last_report_age_seconds=max(0, int((now - last_report).total_seconds())) if last_report else None,
        resolved_at=resolved_at,
        resolution_reason=incident.resolution_reason,
        recovery_reading_id=incident.recovery_reading_id,
        duration_seconds=max(0, int((end - started_at).total_seconds())),
    )


def _page(
    db: Session,
    *,
    statement,
    page: int,
    page_size: int,
) -> MonitoringIncidentPage:
    count_statement = select(func.count()).select_from(statement.order_by(None).subquery())
    total = int(db.scalar(count_statement) or 0)
    incidents = list(
        db.scalars(
            statement.order_by(MonitoringIncident.detected_at.desc(), MonitoringIncident.id.desc())
            .offset((page - 1) * page_size)
            .limit(page_size)
        ).all()
    )
    now = datetime.now(timezone.utc)
    total_pages = (total + page_size - 1) // page_size
    return MonitoringIncidentPage(
        items=[_incident_read(item, now) for item in incidents],
        page=page,
        page_size=page_size,
        total=total,
        total_pages=total_pages,
        has_previous=page > 1,
        has_next=page < total_pages,
    )


def _state_filter(statement, state: Literal["active", "resolved", "all"]):
    if state == "active":
        return statement.where(MonitoringIncident.resolved_at.is_(None))
    if state == "resolved":
        return statement.where(MonitoringIncident.resolved_at.is_not(None))
    return statement


@router.get("/monitoring-incidents", response_model=MonitoringIncidentPage)
def list_monitoring_incidents(
    tank_id: int | None = None,
    state: Literal["active", "resolved", "all"] = Query(default="active"),
    started_after: datetime | None = None,
    started_before: datetime | None = None,
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=25, ge=1, le=100),
    db: Session = Depends(get_db),
    _: User = Depends(require_staff),
) -> MonitoringIncidentPage:
    statement = select(MonitoringIncident).options(selectinload(MonitoringIncident.tank))
    if tank_id is not None:
        statement = statement.where(MonitoringIncident.tank_id == tank_id)
    if started_after is not None:
        statement = statement.where(MonitoringIncident.started_at >= started_after)
    if started_before is not None:
        statement = statement.where(MonitoringIncident.started_at <= started_before)
    if state == "active":
        statement = statement.join(Tank, Tank.id == MonitoringIncident.tank_id).where(Tank.retired_at.is_(None))
    return _page(db, statement=_state_filter(statement, state), page=page, page_size=page_size)


@router.get("/tanks/{tank_id}/monitoring-incidents", response_model=MonitoringIncidentPage)
def list_tank_monitoring_incidents(
    tank_id: int,
    state: Literal["active", "resolved", "all"] = Query(default="active"),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=25, ge=1, le=100),
    db: Session = Depends(get_db),
    _: User = Depends(require_staff),
) -> MonitoringIncidentPage:
    tank_or_404(db, tank_id)
    statement = select(MonitoringIncident).options(selectinload(MonitoringIncident.tank)).where(
        MonitoringIncident.tank_id == tank_id
    )
    if state == "active":
        statement = statement.join(Tank, Tank.id == MonitoringIncident.tank_id).where(Tank.retired_at.is_(None))
    return _page(db, statement=_state_filter(statement, state), page=page, page_size=page_size)

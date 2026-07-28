from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import func, select
from sqlalchemy.orm import Session, selectinload
from app.database import get_db
from app.dependencies import require_admin, require_staff
from app.models import Alert, SensorReading, Tank, ThresholdConfig, ThresholdRevision, User
from app.schemas.analytics import AnalyticsResponse
from app.schemas.dashboard import FleetTankRead
from app.schemas.threshold import ThresholdRead, ThresholdUpdate
from app.services.analytics import build_fleet_analytics
from app.services.decision_engine import status_for_reading
from app.services.species_suitability import evaluate_tank_species_suitability
from app.services.auth_security import audit_event

router = APIRouter(tags=["dashboard"])

@router.get("/fleet", response_model=list[FleetTankRead])
def fleet(db: Session = Depends(get_db), _: User = Depends(require_staff)):
    tanks = db.scalars(select(Tank).options(selectinload(Tank.customer), selectinload(Tank.fish_species)).order_by(Tank.name)).all()
    result = []
    now = datetime.now(timezone.utc)
    for tank in tanks:
        reading = db.scalar(select(SensorReading).where(SensorReading.tank_id == tank.id).order_by(SensorReading.timestamp.desc()).limit(1))
        stamp = reading.timestamp if reading else None
        if stamp and stamp.tzinfo is None: stamp = stamp.replace(tzinfo=timezone.utc)
        unresolved = list(db.scalars(select(Alert).where(Alert.tank_id == tank.id, Alert.is_resolved.is_(False))).all())
        care = evaluate_tank_species_suitability(tank, reading, evaluated_at=now)
        result.append({"id": tank.id, "public_id": tank.public_id, "name": tank.name, "location": tank.location, "customer": {"id": tank.customer.id, "name": tank.customer.name} if tank.customer else None, "latest_reading": reading, "status": status_for_reading(db, reading, evaluated_at=now), "last_reading_at": reading.timestamp if reading else None, "reporting_age_seconds": round((now-stamp).total_seconds()) if stamp else None, "active_warning_count": sum(a.severity.value == "warning" for a in unresolved), "active_critical_count": sum(a.severity.value == "critical" for a in unresolved), "species_care_status": care["status"], "assigned_species_count": len(tank.fish_species)})
    return result

@router.get("/thresholds", response_model=list[ThresholdRead])
def thresholds(db: Session = Depends(get_db), _: User = Depends(require_staff)):
    return list(db.scalars(select(ThresholdConfig).order_by(ThresholdConfig.parameter)).all())

@router.put("/thresholds/{parameter}", response_model=ThresholdRead)
def update_threshold(parameter: str, payload: ThresholdUpdate, request: Request, db: Session = Depends(get_db), current_user: User = Depends(require_admin)):
    item = db.scalar(select(ThresholdConfig).where(ThresholdConfig.parameter == parameter))
    if not item: raise HTTPException(404, "Threshold parameter not found")
    now = datetime.now(timezone.utc)
    if not db.scalar(select(ThresholdRevision.id).where(ThresholdRevision.parameter == parameter).limit(1)):
        earliest = db.scalar(select(SensorReading.timestamp).order_by(SensorReading.timestamp).limit(1))
        db.add(ThresholdRevision(
            parameter=item.parameter, unit=item.unit,
            warning_min=item.warning_min, warning_max=item.warning_max,
            critical_min=item.critical_min, critical_max=item.critical_max,
            enabled=item.enabled, effective_from=earliest or now,
        ))
    for key, value in payload.model_dump().items(): setattr(item, key, value)
    db.add(ThresholdRevision(
        parameter=parameter, unit=payload.unit,
        warning_min=payload.warning_min, warning_max=payload.warning_max,
        critical_min=payload.critical_min, critical_max=payload.critical_max,
        enabled=payload.enabled, effective_from=now,
    ))
    audit_event(db, request, "threshold.write", "success", actor_user_id=current_user.id, target_type="threshold", target_id=parameter)
    db.commit(); db.refresh(item); return item

@router.get("/analytics/fleet", response_model=AnalyticsResponse)
def analytics(
    range: str = Query("24h", pattern="^(24h|7d|30d|custom)$"),
    start: datetime | None = None,
    end: datetime | None = None,
    bucket: str = Query("auto", pattern="^(auto|15m|1h|6h|1d)$"),
    tank_id: list[int] = Query(default=[]),
    db: Session = Depends(get_db),
    _: User = Depends(require_staff),
):
    if len(tank_id) > 3:
        raise HTTPException(422, "Select no more than three tanks")
    if len(set(tank_id)) != len(tank_id):
        raise HTTPException(422, "Tank selections must be unique")
    now = datetime.now(timezone.utc)
    if range == "custom":
        if start is None or end is None:
            raise HTTPException(422, "Custom range requires start and end")
        start = start if start.tzinfo else start.replace(tzinfo=timezone.utc)
        end = end if end.tzinfo else end.replace(tzinfo=timezone.utc)
    else:
        if start is not None or end is not None:
            raise HTTPException(422, "Start and end are only valid for a custom range")
        hours = {"24h": 24, "7d": 168, "30d": 720}[range]
        end, start = now, now - timedelta(hours=hours)
    if start >= end:
        raise HTTPException(422, "Analytics start must be before end")
    duration_seconds = (end - start).total_seconds()
    if duration_seconds > 30 * 86_400:
        raise HTTPException(422, "Analytics range cannot exceed 30 days")
    bucket_seconds = {
        "15m": 900,
        "1h": 3_600,
        "6h": 21_600,
        "1d": 86_400,
    }.get(bucket)
    if bucket_seconds is None:
        bucket_seconds = 900 if duration_seconds <= 86_400 else 3_600 if duration_seconds <= 7 * 86_400 else 21_600
    if (duration_seconds + bucket_seconds - 1) // bucket_seconds > 1_000:
        raise HTTPException(422, "Selected resolution would produce more than 1,000 buckets")
    known_ids = set(db.scalars(select(Tank.id).where(Tank.id.in_(tank_id))).all()) if tank_id else set()
    missing = [value for value in tank_id if value not in known_ids]
    if missing:
        raise HTTPException(422, f"Unknown tank selection: {missing[0]}")
    return build_fleet_analytics(
        db,
        range_name=range,
        start=start,
        end=end,
        bucket_seconds=bucket_seconds,
        selected_tank_ids=tank_id,
    )

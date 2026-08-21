from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import require_admin, require_staff
from app.models import SensorReading, Tank, User
from app.schemas.sensor import SensorReadingCreate, SensorReadingRead
from app.services.decision_engine import ingest_reading
from app.services.auth_security import audit_event

router = APIRouter(prefix="/tanks/{tank_id}/sensors", tags=["sensors"])


def _get_tank_or_404(db: Session, tank_id: int) -> Tank:
    tank = db.scalar(select(Tank).where(Tank.id == tank_id))
    if tank is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Tank not found")
    return tank


@router.get("", response_model=SensorReadingRead)
def get_latest_sensor_reading(
    tank_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_staff),
) -> SensorReading:
    _ = current_user
    _get_tank_or_404(db, tank_id)

    reading = db.scalar(
        select(SensorReading)
        .where(SensorReading.tank_id == tank_id)
        .order_by(SensorReading.received_at.desc(), SensorReading.id.desc())
        .limit(1)
    )
    if reading is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No sensor readings found for this tank",
        )
    return reading


@router.get("/history", response_model=list[SensorReadingRead])
def get_sensor_history(
    tank_id: int,
    start_date: datetime | None = Query(default=None),
    end_date: datetime | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=1000),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_staff),
) -> list[SensorReading]:
    _ = current_user
    _get_tank_or_404(db, tank_id)

    stmt = select(SensorReading).where(SensorReading.tank_id == tank_id)
    if start_date is not None:
        stmt = stmt.where(SensorReading.timestamp >= start_date)
    if end_date is not None:
        stmt = stmt.where(SensorReading.timestamp <= end_date)

    readings = db.scalars(stmt.order_by(SensorReading.received_at.desc(), SensorReading.id.desc()).limit(limit)).all()
    return list(readings)


@router.post("", response_model=SensorReadingRead, status_code=status.HTTP_201_CREATED)
def create_sensor_reading(
    tank_id: int,
    payload: SensorReadingCreate,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
) -> SensorReading:
    _ = current_user
    _get_tank_or_404(db, tank_id)

    values = payload.model_dump()
    timestamp = values.pop("timestamp", None)
    if timestamp is not None:
        values["timestamp"] = timestamp
    reading = ingest_reading(db, tank_id, values, device_id=None)
    audit_event(db, request, "sensor.write", "success", actor_user_id=current_user.id, target_type="tank", target_id=tank_id)
    db.commit()
    return reading

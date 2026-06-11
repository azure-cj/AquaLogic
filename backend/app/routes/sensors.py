from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user
from app.models import SensorReading, Tank, User
from app.schemas.sensor import SensorReadingCreate, SensorReadingRead

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
    current_user: User = Depends(get_current_user),
) -> SensorReading:
    _ = current_user
    _get_tank_or_404(db, tank_id)

    reading = db.scalar(
        select(SensorReading)
        .where(SensorReading.tank_id == tank_id)
        .order_by(SensorReading.timestamp.desc())
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
    current_user: User = Depends(get_current_user),
) -> list[SensorReading]:
    _ = current_user
    _get_tank_or_404(db, tank_id)

    stmt = select(SensorReading).where(SensorReading.tank_id == tank_id)
    if start_date is not None:
        stmt = stmt.where(SensorReading.timestamp >= start_date)
    if end_date is not None:
        stmt = stmt.where(SensorReading.timestamp <= end_date)

    readings = db.scalars(stmt.order_by(SensorReading.timestamp.desc()).limit(limit)).all()
    return list(readings)


@router.post("", response_model=SensorReadingRead, status_code=status.HTTP_201_CREATED)
def create_sensor_reading(
    tank_id: int,
    payload: SensorReadingCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> SensorReading:
    _ = current_user
    _get_tank_or_404(db, tank_id)

    reading = SensorReading(
        tank_id=tank_id,
        temperature=payload.temperature,
        ph=payload.ph,
        turbidity=payload.turbidity,
        dissolved_oxygen=payload.dissolved_oxygen,
        tds=payload.tds,
        ammonia=payload.ammonia,
        is_mock=payload.is_mock,
    )
    if payload.timestamp is not None:
        reading.timestamp = payload.timestamp

    db.add(reading)
    db.commit()
    db.refresh(reading)
    return reading

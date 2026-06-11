from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.database import get_db
from app.models import SensorReading, Tank
from app.schemas.tank import TankPublicRead

router = APIRouter(prefix="/public", tags=["public"])


@router.get("/tanks/{tank_id}", response_model=TankPublicRead)
def get_public_tank_view(
    tank_id: int,
    db: Session = Depends(get_db),
) -> TankPublicRead:
    tank = db.scalar(
        select(Tank)
        .options(selectinload(Tank.fish_species))
        .where(Tank.id == tank_id)
    )
    if tank is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Tank not found")

    latest_reading = db.scalar(
        select(SensorReading)
        .where(SensorReading.tank_id == tank_id)
        .order_by(SensorReading.timestamp.desc())
        .limit(1)
    )

    return TankPublicRead(
        id=tank.id,
        name=tank.name,
        location=tank.location,
        description=tank.description,
        fish_species=tank.fish_species,
        latest_reading=latest_reading,
    )

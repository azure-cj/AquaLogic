from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.database import get_db
from app.models import SensorReading, Tank
from app.schemas.tank import TankPublicRead
from app.services.decision_engine import parameter_statuses, status_for_reading

router = APIRouter(prefix="/public", tags=["public"])


@router.get("/tanks/{public_id}", response_model=TankPublicRead, response_model_exclude_none=True)
def get_public_tank_view(
    public_id: str,
    db: Session = Depends(get_db),
) -> TankPublicRead:
    stmt = select(Tank).options(selectinload(Tank.fish_species)).where(Tank.is_public.is_(True))
    tank = db.scalar(stmt.where(Tank.public_id == public_id))
    if tank is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Tank not found")

    latest_reading = db.scalar(
        select(SensorReading)
        .where(SensorReading.tank_id == tank.id)
        .order_by(SensorReading.timestamp.desc())
        .limit(1)
    )

    return TankPublicRead(
        public_id=tank.public_id,
        name=tank.name,
        display_location=tank.public_location,
        description=tank.description,
        habitat_label=tank.habitat_label,
        water_type=tank.water_type,
        volume_liters=tank.volume_liters,
        established_on=tank.established_on,
        hero_image_url=tank.hero_image_url,
        fish_species=tank.fish_species,
        latest_reading=latest_reading,
        status=status_for_reading(db, latest_reading),
        parameter_statuses=parameter_statuses(db, latest_reading),
        public_care_notes=tank.public_care_notes,
    )

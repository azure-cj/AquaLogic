from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.database import get_db
from app.dependencies import require_staff
from app.models import SensorReading, Tank, User
from app.schemas.species_suitability import SpeciesSuitabilityResponse
from app.services.species_suitability import evaluate_tank_species_suitability


router = APIRouter(prefix="/tanks", tags=["species suitability"])


@router.get("/{tank_id}/species-suitability", response_model=SpeciesSuitabilityResponse)
def get_species_suitability(
    tank_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_staff),
) -> dict:
    _ = current_user
    tank = db.scalar(select(Tank).options(selectinload(Tank.fish_species)).where(Tank.id == tank_id))
    if tank is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Tank not found")
    reading = db.scalar(
        select(SensorReading)
        .where(SensorReading.tank_id == tank_id)
        .order_by(SensorReading.received_at.desc(), SensorReading.id.desc())
        .limit(1)
    )
    return evaluate_tank_species_suitability(tank, reading)

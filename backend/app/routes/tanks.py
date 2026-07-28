from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from app.database import get_db
from app.dependencies import require_password_change_complete
from app.models import Alert, Customer, FishSpecies, SensorReading, Tank, TankFish, User
from app.schemas.fish import FishAssignmentRequest
from app.schemas.operations import TankOperationsResponse
from app.schemas.tank import TankCreate, TankDetail, TankRead, TankUpdate
from app.services.decision_engine import parameter_statuses, status_for_reading
from datetime import datetime, timezone

router = APIRouter(prefix="/tanks", tags=["tanks"])


def _get_tank_or_404(db: Session, tank_id: int) -> Tank:
    tank = db.scalar(
        select(Tank)
        .options(selectinload(Tank.fish_species), selectinload(Tank.customer))
        .where(Tank.id == tank_id)
    )
    if tank is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Tank not found")
    return tank


@router.get("", response_model=list[TankRead])
def list_tanks(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_password_change_complete),
) -> list[Tank]:
    _ = current_user
    tanks = db.scalars(select(Tank).order_by(Tank.id)).all()
    return list(tanks)


@router.get("/{tank_id}", response_model=TankDetail)
def get_tank(
    tank_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_password_change_complete),
) -> Tank:
    _ = current_user
    return _get_tank_or_404(db, tank_id)


@router.get("/{tank_id}/operations", response_model=TankOperationsResponse)
def get_tank_operations(
    tank_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_password_change_complete),
) -> dict:
    _ = current_user
    _get_tank_or_404(db, tank_id)
    evaluated_at = datetime.now(timezone.utc)
    reading = db.scalar(
        select(SensorReading)
        .where(SensorReading.tank_id == tank_id)
        .order_by(SensorReading.timestamp.desc())
        .limit(1)
    )
    active_alerts = list(
        db.scalars(
            select(Alert)
            .where(Alert.tank_id == tank_id, Alert.is_resolved.is_(False))
            .order_by(Alert.created_at.desc())
        ).all()
    )
    return {
        "tank_id": tank_id,
        "evaluated_at": evaluated_at,
        "status": status_for_reading(db, reading, evaluated_at=evaluated_at),
        "latest_reading": reading,
        "parameter_statuses": parameter_statuses(db, reading, evaluated_at=evaluated_at),
        "active_alerts": active_alerts,
    }


@router.post("", response_model=TankRead, status_code=status.HTTP_201_CREATED)
def create_tank(
    payload: TankCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_password_change_complete),
) -> Tank:
    _ = current_user
    if payload.customer_id is not None and not db.get(Customer, payload.customer_id):
        raise HTTPException(status_code=404, detail="Customer not found")
    tank = Tank(**payload.dict())
    db.add(tank)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A tank with this name already exists",
        )
    db.refresh(tank)
    return tank


@router.put("/{tank_id}", response_model=TankRead)
def update_tank(
    tank_id: int,
    payload: TankUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_password_change_complete),
) -> Tank:
    _ = current_user
    tank = _get_tank_or_404(db, tank_id)
    updates = payload.dict(exclude_unset=True)
    if updates.get("customer_id") is not None and not db.get(Customer, updates["customer_id"]):
        raise HTTPException(status_code=404, detail="Customer not found")
    if not updates:
        return tank

    for key, value in updates.items():
        setattr(tank, key, value)

    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A tank with this name already exists",
        )
    db.refresh(tank)
    return tank


@router.delete("/{tank_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_tank(
    tank_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_password_change_complete),
) -> Response:
    _ = current_user
    tank = _get_tank_or_404(db, tank_id)
    db.delete(tank)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/{tank_id}/fish", status_code=status.HTTP_201_CREATED)
def assign_fish_to_tank(
    tank_id: int,
    payload: FishAssignmentRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_password_change_complete),
) -> dict[str, str]:
    _ = current_user
    _get_tank_or_404(db, tank_id)

    fish = db.scalar(select(FishSpecies).where(FishSpecies.id == payload.fish_species_id))
    if fish is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Fish species not found",
        )

    existing = db.scalar(
        select(TankFish).where(
            TankFish.tank_id == tank_id,
            TankFish.fish_species_id == payload.fish_species_id,
        )
    )
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Fish species is already assigned to this tank",
        )

    db.add(TankFish(tank_id=tank_id, fish_species_id=payload.fish_species_id))
    db.commit()
    return {"message": "Fish species assigned to tank"}


@router.delete("/{tank_id}/fish/{fish_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_fish_from_tank(
    tank_id: int,
    fish_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_password_change_complete),
) -> Response:
    _ = current_user
    _get_tank_or_404(db, tank_id)

    link = db.scalar(
        select(TankFish).where(
            TankFish.tank_id == tank_id,
            TankFish.fish_species_id == fish_id,
        )
    )
    if link is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Fish assignment not found",
        )

    db.delete(link)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.database import get_db
from app.dependencies import require_password_change_complete
from app.models import FishSpecies, User
from app.schemas.fish import FishSpeciesCreate, FishSpeciesRead, FishSpeciesUpdate, validate_preferred_range_order

router = APIRouter(prefix="/fish", tags=["fish"])


def _get_fish_or_404(db: Session, fish_id: int) -> FishSpecies:
    fish = db.scalar(
        select(FishSpecies)
        .options(selectinload(FishSpecies.tank_links))
        .where(FishSpecies.id == fish_id)
    )
    if fish is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Fish species not found",
        )
    return fish


@router.get("", response_model=list[FishSpeciesRead])
def list_fish_species(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_password_change_complete),
) -> list[FishSpecies]:
    _ = current_user
    species = db.scalars(
        select(FishSpecies)
        .options(selectinload(FishSpecies.tank_links))
        .order_by(FishSpecies.category, FishSpecies.common_name)
    ).all()
    return list(species)


@router.get("/{fish_id}", response_model=FishSpeciesRead)
def get_fish_species(
    fish_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_password_change_complete),
) -> FishSpecies:
    _ = current_user
    return _get_fish_or_404(db, fish_id)


@router.post("", response_model=FishSpeciesRead, status_code=status.HTTP_201_CREATED)
def create_fish_species(
    payload: FishSpeciesCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_password_change_complete),
) -> FishSpecies:
    _ = current_user
    fish = FishSpecies(**payload.dict())
    db.add(fish)
    db.commit()
    db.refresh(fish)
    return fish


@router.put("/{fish_id}", response_model=FishSpeciesRead)
def update_fish_species(
    fish_id: int,
    payload: FishSpeciesUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_password_change_complete),
) -> FishSpecies:
    _ = current_user
    fish = _get_fish_or_404(db, fish_id)

    updates = payload.dict(exclude_unset=True)
    if not updates:
        return fish

    effective_ranges = {
        key: updates.get(key, getattr(fish, key))
        for key in (
            "ideal_temp_min", "ideal_temp_max", "ideal_ph_min", "ideal_ph_max",
            "ideal_tds_min", "ideal_tds_max",
        )
    }
    try:
        validate_preferred_range_order(effective_ranges)
    except ValueError as error:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(error))

    for key, value in updates.items():
        setattr(fish, key, value)

    db.commit()
    db.refresh(fish)
    return fish


@router.delete("/{fish_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_fish_species(
    fish_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_password_change_complete),
) -> Response:
    _ = current_user
    fish = _get_fish_or_404(db, fish_id)
    if fish.tank_count:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                f"Fish species is assigned to {fish.tank_count} "
                f"{'tank' if fish.tank_count == 1 else 'tanks'}"
            ),
        )
    db.delete(fish)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)

from pathlib import Path
from uuid import uuid4

from fastapi import APIRouter, Depends, File, HTTPException, Request, Response, UploadFile, status
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.database import get_db
from app.dependencies import require_admin, require_staff
from app.config import settings
from app.models import FishSpecies, TankFish, User
from app.schemas.fish import (
    FishSpeciesCreate,
    FishSpeciesDirectoryRead,
    FishImageUploadRead,
    FishSpeciesRead,
    FishSpeciesUpdate,
    validate_preferred_range_order,
)
from app.services.auth_security import audit_event

router = APIRouter(prefix="/fish", tags=["fish"])

FISH_IMAGE_TYPES = {
    "image/jpeg": (".jpg", b"\xff\xd8\xff"),
    "image/png": (".png", b"\x89PNG\r\n\x1a\n"),
    "image/webp": (".webp", b"RIFF"),
}


def _remove_local_photo(photo_url: str | None) -> None:
    if not photo_url or not photo_url.startswith("/api/media/fish/"):
        return
    relative_name = photo_url.removeprefix("/api/media/")
    target = (Path(settings.media_root) / relative_name).resolve()
    media_root = Path(settings.media_root).resolve()
    if media_root not in target.parents or not target.is_file():
        return
    target.unlink()


def _get_fish_or_404(db: Session, fish_id: int) -> FishSpecies:
    fish = db.scalar(
        select(FishSpecies)
        .options(selectinload(FishSpecies.tank_links).selectinload(TankFish.tank))
        .where(FishSpecies.id == fish_id)
    )
    if fish is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Fish species not found",
        )
    return fish


@router.get("", response_model=list[FishSpeciesDirectoryRead])
def list_fish_species(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_staff),
) -> list[FishSpecies]:
    _ = current_user
    species = db.scalars(
        select(FishSpecies)
        .options(selectinload(FishSpecies.tank_links).selectinload(TankFish.tank))
        .order_by(FishSpecies.category, FishSpecies.common_name)
    ).all()
    return list(species)


@router.get("/{fish_id}", response_model=FishSpeciesDirectoryRead)
def get_fish_species(
    fish_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_staff),
) -> FishSpecies:
    _ = current_user
    return _get_fish_or_404(db, fish_id)


@router.post("", response_model=FishSpeciesRead, status_code=status.HTTP_201_CREATED)
def create_fish_species(
    payload: FishSpeciesCreate,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
) -> FishSpecies:
    _ = current_user
    fish = FishSpecies(**payload.model_dump())
    db.add(fish)
    db.flush()
    audit_event(db, request, "fish.create", "success", actor_user_id=current_user.id, target_type="fish", target_id=fish.id)
    db.commit()
    db.refresh(fish)
    return fish


@router.put("/{fish_id}", response_model=FishSpeciesRead)
def update_fish_species(
    fish_id: int,
    payload: FishSpeciesUpdate,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
) -> FishSpecies:
    _ = current_user
    fish = _get_fish_or_404(db, fish_id)

    updates = payload.model_dump(exclude_unset=True)
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
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail=str(error))

    previous_photo_url = fish.photo_url
    for key, value in updates.items():
        setattr(fish, key, value)

    audit_event(db, request, "fish.update", "success", actor_user_id=current_user.id, target_type="fish", target_id=fish.id)
    db.commit()
    db.refresh(fish)
    if "photo_url" in updates and updates["photo_url"] != previous_photo_url:
        _remove_local_photo(previous_photo_url)
    return fish


@router.post("/{fish_id}/photo-image", response_model=FishImageUploadRead)
def upload_fish_photo(
    fish_id: int,
    request: Request,
    image: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
) -> dict[str, str | int]:
    fish = _get_fish_or_404(db, fish_id)
    image_type = FISH_IMAGE_TYPES.get(image.content_type or "")
    if image_type is None:
        raise HTTPException(status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, detail="Use a JPG, PNG, or WebP image")

    extension, magic = image_type
    header = image.file.read(12)
    image.file.seek(0)
    valid_header = header.startswith(magic)
    if image.content_type == "image/webp":
        valid_header = valid_header and header[8:12] == b"WEBP"
    if not valid_header:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="The uploaded file is not a valid image")

    media_directory = Path(settings.media_root) / "fish"
    media_directory.mkdir(parents=True, exist_ok=True)
    filename = f"{uuid4().hex}{extension}"
    target = media_directory / filename
    size_bytes = 0
    try:
        with target.open("wb") as saved_image:
            while chunk := image.file.read(64 * 1024):
                size_bytes += len(chunk)
                if size_bytes > settings.max_fish_image_bytes:
                    raise HTTPException(status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, detail="Fish photos must be 5 MB or smaller")
                saved_image.write(chunk)
    except HTTPException:
        target.unlink(missing_ok=True)
        raise
    except OSError:
        target.unlink(missing_ok=True)
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="The image could not be stored")

    previous_url = fish.photo_url
    fish.photo_url = f"/api/media/fish/{filename}"
    audit_event(db, request, "fish.photo_upload", "success", actor_user_id=current_user.id, target_type="fish", target_id=fish.id)
    try:
        db.commit()
    except Exception:
        db.rollback()
        target.unlink(missing_ok=True)
        raise
    db.refresh(fish)
    _remove_local_photo(previous_url)
    return {
        "photo_url": fish.photo_url,
        "content_type": image.content_type or "image/jpeg",
        "size_bytes": size_bytes,
    }


@router.delete("/{fish_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_fish_species(
    fish_id: int,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
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
    audit_event(db, request, "fish.delete", "success", actor_user_id=current_user.id, target_type="fish", target_id=fish.id)
    db.delete(fish)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)

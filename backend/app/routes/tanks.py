import logging
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

from fastapi import APIRouter, Depends, File, HTTPException, Query, Request, Response, UploadFile, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from app.config import settings
from app.database import get_db
from app.dependencies import require_admin, require_staff
from app.models import Alert, Customer, FishSpecies, RegisteredDevice, SensorReading, Tank, TankFish, User
from app.schemas.fish import FishAssignmentRequest
from app.schemas.operations import TankOperationsResponse
from app.schemas.tank import HeroImageUploadRead, TankCreate, TankDetail, TankRetireRequest, TankRead, TankUpdate
from app.services.auth_security import audit_event
from app.services.decision_engine import parameter_statuses, status_for_reading
from app.services.tank_lifecycle import (
    RETIREMENT_BLOCKED_BY_ACTUATOR_DETAIL,
    lock_tank_for_mutation,
    require_active_tank,
    uncleared_actuator_work,
)
from app.services.monitoring_incidents import resolve_active_monitoring_incident


router = APIRouter(prefix="/tanks", tags=["tanks"])
logger = logging.getLogger(__name__)

HERO_IMAGE_TYPES = {
    "image/jpeg": (".jpg", b"\xff\xd8\xff"),
    "image/png": (".png", b"\x89PNG\r\n\x1a\n"),
    "image/webp": (".webp", b"RIFF"),
}


def _remove_local_hero_image(image_url: str | None) -> None:
    if not image_url or not image_url.startswith("/api/media/tanks/"):
        return
    relative_name = image_url.removeprefix("/api/media/")
    target = (Path(settings.media_root) / relative_name).resolve()
    media_root = Path(settings.media_root).resolve()
    if media_root not in target.parents or not target.is_file():
        return
    try:
        target.unlink()
    except OSError:
        logger.warning(
            "Tank-owned hero image cleanup failed after the database change: %s",
            relative_name,
            exc_info=True,
        )


def _get_tank_or_404(db: Session, tank_id: int) -> Tank:
    tank = db.scalar(
        select(Tank)
        .options(
            selectinload(Tank.fish_species),
            selectinload(Tank.customer),
            selectinload(Tank.retired_by_user),
        )
        .where(Tank.id == tank_id)
    )
    if tank is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Tank not found")
    return tank


@router.get("", response_model=list[TankRead])
def list_tanks(
    lifecycle: str = Query(default="active", pattern="^(active|retired|all)$"),
    db: Session = Depends(get_db),
    _: User = Depends(require_staff),
) -> list[Tank]:
    stmt = select(Tank).options(selectinload(Tank.retired_by_user)).order_by(Tank.id)
    if lifecycle == "active":
        stmt = stmt.where(Tank.retired_at.is_(None))
    elif lifecycle == "retired":
        stmt = stmt.where(Tank.retired_at.is_not(None))
    return list(db.scalars(stmt).all())


@router.get("/{tank_id}", response_model=TankDetail)
def get_tank(tank_id: int, db: Session = Depends(get_db), _: User = Depends(require_staff)) -> Tank:
    return _get_tank_or_404(db, tank_id)


@router.get("/{tank_id}/operations", response_model=TankOperationsResponse)
def get_tank_operations(tank_id: int, db: Session = Depends(get_db), _: User = Depends(require_staff)) -> dict:
    tank = _get_tank_or_404(db, tank_id)
    evaluated_at = datetime.now(timezone.utc)
    reading = db.scalar(select(SensorReading).where(SensorReading.tank_id == tank_id).order_by(SensorReading.received_at.desc(), SensorReading.id.desc()).limit(1))
    active_alerts = list(db.scalars(select(Alert).where(Alert.tank_id == tank_id, Alert.is_resolved.is_(False)).order_by(Alert.created_at.desc())).all())
    return {
        "tank_id": tank_id,
        "evaluated_at": evaluated_at,
        "status": "retired" if tank.retired_at is not None else status_for_reading(db, reading, evaluated_at=evaluated_at),
        "latest_reading": reading,
        "parameter_statuses": parameter_statuses(db, reading, evaluated_at=evaluated_at),
        "active_alerts": active_alerts,
    }


@router.post("", response_model=TankRead, status_code=status.HTTP_201_CREATED)
def create_tank(payload: TankCreate, request: Request, db: Session = Depends(get_db), current_user: User = Depends(require_admin)) -> Tank:
    if payload.customer_id is not None and not db.get(Customer, payload.customer_id):
        raise HTTPException(status_code=404, detail="Customer not found")
    tank = Tank(**payload.model_dump())
    db.add(tank)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="A tank with this name already exists")
    audit_event(db, request, "tank.create", "success", actor_user_id=current_user.id, target_type="tank", target_id=tank.id)
    db.commit()
    db.refresh(tank)
    return tank


@router.put("/{tank_id}", response_model=TankRead)
def update_tank(tank_id: int, payload: TankUpdate, request: Request, db: Session = Depends(get_db), current_user: User = Depends(require_admin)) -> Tank:
    tank = _get_tank_or_404(db, tank_id)
    require_active_tank(tank)
    updates = payload.model_dump(exclude_unset=True)
    if updates.get("customer_id") is not None and not db.get(Customer, updates["customer_id"]):
        raise HTTPException(status_code=404, detail="Customer not found")
    if not updates:
        return tank
    for key, value in updates.items():
        setattr(tank, key, value)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="A tank with this name already exists")
    event = "tank.public_visibility" if "is_public" in updates else "tank.update"
    audit_event(db, request, event, "success", actor_user_id=current_user.id, target_type="tank", target_id=tank.id)
    db.commit()
    db.refresh(tank)
    return tank


@router.post("/{tank_id}/hero-image", response_model=HeroImageUploadRead)
def upload_hero_image(
    tank_id: int,
    request: Request,
    image: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
) -> dict[str, str | int]:
    tank = _get_tank_or_404(db, tank_id)
    require_active_tank(tank)
    image_type = HERO_IMAGE_TYPES.get(image.content_type or "")
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

    media_directory = Path(settings.media_root) / "tanks"
    media_directory.mkdir(parents=True, exist_ok=True)
    filename = f"{uuid4().hex}{extension}"
    target = media_directory / filename
    size_bytes = 0
    try:
        with target.open("wb") as saved_image:
            while chunk := image.file.read(64 * 1024):
                size_bytes += len(chunk)
                if size_bytes > settings.max_hero_image_bytes:
                    raise HTTPException(status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, detail="Hero images must be 5 MB or smaller")
                saved_image.write(chunk)
    except HTTPException:
        target.unlink(missing_ok=True)
        raise
    except OSError:
        target.unlink(missing_ok=True)
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="The image could not be stored")

    previous_url = tank.hero_image_url
    tank.hero_image_url = f"/api/media/tanks/{filename}"
    audit_event(db, request, "tank.hero_image_upload", "success", actor_user_id=current_user.id, target_type="tank", target_id=tank.id)
    try:
        db.commit()
    except Exception:
        db.rollback()
        target.unlink(missing_ok=True)
        raise
    db.refresh(tank)
    _remove_local_hero_image(previous_url)
    return {
        "hero_image_url": tank.hero_image_url,
        "content_type": image.content_type or "image/jpeg",
        "size_bytes": size_bytes,
    }


@router.post("/{tank_id}/retire", response_model=TankDetail)
def retire_tank(
    tank_id: int,
    payload: TankRetireRequest,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
) -> Tank:
    tank = lock_tank_for_mutation(db, tank_id)
    if tank.retired_at is not None:
        db.commit()
        return _get_tank_or_404(db, tank_id)

    blocking_command = uncleared_actuator_work(db, tank_id)
    if blocking_command is not None:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=RETIREMENT_BLOCKED_BY_ACTUATOR_DETAIL,
        )

    retired_at = datetime.now(timezone.utc)
    active_devices = list(
        db.scalars(
            select(RegisteredDevice).where(RegisteredDevice.tank_id == tank_id)
        ).all()
    )
    was_monitoring_expected = tank.monitoring_expected_at is not None
    tank.retired_at = retired_at
    tank.retired_by_user_id = current_user.id
    tank.retirement_note = payload.note
    tank.is_public = False
    tank.monitoring_expected_at = None
    resolve_active_monitoring_incident(
        db,
        tank_id,
        reason="tank_retired",
        resolved_at=retired_at,
    )
    deactivated_device_count = sum(device.is_active for device in active_devices)
    for device in active_devices:
        device.is_active = False
    audit_event(
        db,
        request,
        "tank.retire",
        "success",
        actor_user_id=current_user.id,
        target_type="tank",
        target_id=tank.id,
        details={
            "retired_at": retired_at.isoformat(),
            "deactivated_device_count": deactivated_device_count,
            "monitoring_expectation_cleared": was_monitoring_expected,
            "incident_resolution": "tank_retired",
        },
    )
    db.commit()
    return _get_tank_or_404(db, tank_id)


@router.delete("/{tank_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_tank(tank_id: int, request: Request, db: Session = Depends(get_db), current_user: User = Depends(require_admin)) -> Response:
    # Permanent deletion is a lifecycle mutation too. Take the same tank lock
    # used by retirement and device writes before checking/deleting the row so
    # concurrent delete/retire attempts cannot observe contradictory state.
    tank = lock_tank_for_mutation(db, tank_id)
    if tank.retired_at is None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Tank must be retired before permanent deletion",
        )
    hero_image_url = tank.hero_image_url
    audit_event(db, request, "tank.delete", "success", actor_user_id=current_user.id, target_type="tank", target_id=tank.id)
    db.delete(tank)
    db.commit()
    _remove_local_hero_image(hero_image_url)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/{tank_id}/fish", status_code=status.HTTP_201_CREATED)
def assign_fish_to_tank(tank_id: int, payload: FishAssignmentRequest, request: Request, db: Session = Depends(get_db), current_user: User = Depends(require_staff)) -> dict[str, str]:
    require_active_tank(_get_tank_or_404(db, tank_id))
    fish = db.scalar(select(FishSpecies).where(FishSpecies.id == payload.fish_species_id))
    if fish is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Fish species not found")
    if db.scalar(select(TankFish).where(TankFish.tank_id == tank_id, TankFish.fish_species_id == payload.fish_species_id)):
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Fish species is already assigned to this tank")
    db.add(TankFish(tank_id=tank_id, fish_species_id=payload.fish_species_id))
    audit_event(db, request, "tank.fish_assign", "success", actor_user_id=current_user.id, target_type="tank", target_id=tank_id)
    db.commit()
    return {"message": "Fish species assigned to tank"}


@router.delete("/{tank_id}/fish/{fish_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_fish_from_tank(tank_id: int, fish_id: int, request: Request, db: Session = Depends(get_db), current_user: User = Depends(require_staff)) -> Response:
    require_active_tank(_get_tank_or_404(db, tank_id))
    link = db.scalar(select(TankFish).where(TankFish.tank_id == tank_id, TankFish.fish_species_id == fish_id))
    if link is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Fish assignment not found")
    audit_event(db, request, "tank.fish_remove", "success", actor_user_id=current_user.id, target_type="tank", target_id=tank_id)
    db.delete(link)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)

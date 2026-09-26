from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_auth_session, require_staff
from app.models import AuthSession, PushDevice, User
from app.schemas.push_device import PushDeviceRead, PushDeviceRegistration
from app.security import utc_now


router = APIRouter(prefix="/push/devices", tags=["push devices"])


def _upsert_registration(
    db: Session,
    *,
    current_user: User,
    current_session: AuthSession,
    payload: PushDeviceRegistration,
) -> PushDevice:
    installation_id = str(payload.installation_id)
    device = db.scalar(
        select(PushDevice)
        .where(PushDevice.installation_id == installation_id)
        .with_for_update()
    )
    fid_device = None
    if payload.firebase_installation_id is not None:
        fid_device = db.scalar(
            select(PushDevice)
            .where(PushDevice.firebase_installation_id == payload.firebase_installation_id)
            .with_for_update()
        )
    token_device = db.scalar(
        select(PushDevice)
        .where(PushDevice.fcm_token == payload.fcm_token)
        .with_for_update()
    )

    # Keep the stable AquaLogic installation row when it exists. If secure
    # storage was recreated, a matching FID can recover the existing row. A
    # token or FID presented by another row is moved transactionally so every
    # identifier remains unique.
    if device is None and fid_device is not None:
        device = fid_device
    duplicate_ids = {
        candidate.id
        for candidate in (fid_device, token_device)
        if candidate is not None and (device is None or candidate.id != device.id)
    }
    if duplicate_ids:
        db.execute(
            PushDevice.__table__.delete().where(PushDevice.id.in_(duplicate_ids))
        )
        db.flush()

    now = utc_now()
    if device is None:
        device = PushDevice(
            installation_id=installation_id,
            fcm_token=payload.fcm_token,
            firebase_installation_id=payload.firebase_installation_id,
            platform=payload.platform,
            user_id=current_user.id,
            auth_session_id=current_session.id,
            is_active=True,
            last_registered_at=now,
            disabled_at=None,
        )
        db.add(device)
    else:
        device.installation_id = installation_id
        device.fcm_token = payload.fcm_token
        # Older app versions can refresh their distinct FCM token without
        # clearing an FID already registered by a newer client.
        if payload.firebase_installation_id is not None:
            device.firebase_installation_id = payload.firebase_installation_id
        device.platform = payload.platform
        device.user_id = current_user.id
        device.auth_session_id = current_session.id
        device.is_active = True
        device.last_registered_at = now
        device.disabled_at = None
    return device


@router.put("/current", response_model=PushDeviceRead)
def register_current_device(
    payload: PushDeviceRegistration,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_staff),
    current_session: AuthSession = Depends(get_current_auth_session),
) -> PushDevice:
    # Unique constraints are the final concurrency barrier. Retry once after a
    # competing registration commits so identical requests remain idempotent.
    for attempt in range(2):
        try:
            device = _upsert_registration(
                db,
                current_user=current_user,
                current_session=current_session,
                payload=payload,
            )
            db.commit()
            db.refresh(device)
            return device
        except IntegrityError:
            db.rollback()
            if attempt == 1:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Device registration changed concurrently; retry the request",
                ) from None
    raise AssertionError("unreachable")


@router.delete("/current/{installation_id}", status_code=status.HTTP_204_NO_CONTENT)
def deactivate_current_device(
    installation_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_staff),
    current_session: AuthSession = Depends(get_current_auth_session),
) -> None:
    device = db.scalar(
        select(PushDevice)
        .where(
            PushDevice.installation_id == str(installation_id),
            PushDevice.user_id == current_user.id,
            PushDevice.auth_session_id == current_session.id,
        )
        .with_for_update()
    )
    if device is not None and device.is_active:
        device.is_active = False
        device.disabled_at = utc_now()
        device.updated_at = utc_now()
        db.commit()

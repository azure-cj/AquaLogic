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
    token_device = db.scalar(
        select(PushDevice)
        .where(PushDevice.fcm_token == payload.fcm_token)
        .with_for_update()
    )

    # FCM tokens identify one app installation. If a reinstall or stale local
    # installation ID presents the same token, discard the old registration
    # in this transaction before assigning the token to the current identity.
    if token_device is not None and (device is None or token_device.id != device.id):
        db.delete(token_device)
        db.flush()

    now = utc_now()
    if device is None:
        device = PushDevice(
            installation_id=installation_id,
            fcm_token=payload.fcm_token,
            platform=payload.platform,
            user_id=current_user.id,
            auth_session_id=current_session.id,
            is_active=True,
            last_registered_at=now,
            disabled_at=None,
        )
        db.add(device)
    else:
        device.fcm_token = payload.fcm_token
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

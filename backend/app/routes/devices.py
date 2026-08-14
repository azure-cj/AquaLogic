"""Read-only bridge registration and ingestion endpoints; no actuator surface."""
from datetime import timezone

from fastapi import APIRouter, Depends, Header, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import require_admin
from app.models import RegisteredDevice, Tank, User
from app.schemas.device import DeviceCreate, DeviceProvisioned
from app.schemas.sensor import DeviceReadingCreate, SensorReadingRead
from app.security import hash_opaque_token, opaque_token, utc_now
from app.services.auth_security import audit_event
from app.services.decision_engine import ingest_reading

router = APIRouter(tags=["devices"])


@router.post("/devices", response_model=DeviceProvisioned, status_code=status.HTTP_201_CREATED)
def register_device(payload: DeviceCreate, request: Request, db: Session = Depends(get_db), current_user: User = Depends(require_admin)):
    if db.get(Tank, payload.tank_id) is None:
        raise HTTPException(404, "Tank not found")
    raw_key = opaque_token()
    device = RegisteredDevice(id=payload.device_id, tank_id=payload.tank_id, key_hash=hash_opaque_token(raw_key))
    db.add(device)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "Device ID already exists")
    audit_event(db, request, "device.register", "success", actor_user_id=current_user.id, target_type="device", target_id=device.id, details={"tank_id": device.tank_id})
    db.commit()
    return DeviceProvisioned(device_id=device.id, tank_id=device.tank_id, device_key=raw_key)


@router.post("/device-ingestion/readings", response_model=SensorReadingRead, status_code=status.HTTP_201_CREATED)
def ingest_device_reading(payload: DeviceReadingCreate, request: Request, x_device_key: str = Header(...), db: Session = Depends(get_db)):
    device = db.scalar(select(RegisteredDevice).where(RegisteredDevice.key_hash == hash_opaque_token(x_device_key)))
    if device is None or not device.is_active:
        audit_event(db, request, "device.ingest", "denied", target_type="device")
        db.commit()
        raise HTTPException(status_code=401, detail="Invalid device key")
    values = payload.model_dump(exclude={"observed_at"})
    values.update({"dissolved_oxygen": None, "ammonia": None, "is_mock": False})
    if payload.observed_at is not None:
        observed_at = payload.observed_at
        values["timestamp"] = observed_at.replace(tzinfo=timezone.utc) if observed_at.tzinfo is None else observed_at
    reading = ingest_reading(db, device.tank_id, values)
    device.last_seen_at = utc_now()
    audit_event(db, request, "device.ingest", "success", target_type="device", target_id=device.id, details={"tank_id": device.tank_id, "reading_id": reading.id})
    db.commit()
    db.refresh(reading)
    return reading

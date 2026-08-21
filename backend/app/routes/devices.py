"""Registered-device ingestion and the private bridge actuator boundary."""

from __future__ import annotations

import json
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

from fastapi import APIRouter, Depends, Header, HTTPException, Query, Request, status
from sqlalchemy import func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import require_admin
from app.models import (
    ActuatorCommand,
    ActuatorState,
    ActuatorStateHistory,
    RegisteredDevice,
    Tank,
    User,
)
from app.schemas.device import (
    ActuatorCommandCreate,
    ActuatorCommandFailure,
    ActuatorCommandHistoryPage,
    ActuatorCommandRead,
    ActuatorCommandResult,
    ActuatorHistorySummary,
    ActuatorName,
    ActuatorStateRead,
    ActuatorStateReport,
    CommandStatus,
    DeviceActuatorStatusRead,
    DeviceCreate,
    DeviceKeyRotated,
    DeviceRead,
    DeviceProvisioned,
    DeviceUpdate,
    PendingActuatorCommand,
    COMMAND_EXPIRY_DEFAULT_SECONDS,
)
from app.schemas.sensor import DeviceReadingCreate, SensorReadingRead
from app.security import hash_opaque_token, opaque_token, utc_now
from app.services.auth_security import audit_event
from app.services.decision_engine import ingest_reading


router = APIRouter(tags=["devices"])
ACTUATORS = ("uv", "led", "feeder", "pump_a", "pump_b")
PUMP_ACTUATORS = {"pump_a", "pump_b"}
DEVICE_ONLINE_WINDOW_SECONDS = 90


def _explicit_utc(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value


def _json_object(value: str | None) -> dict[str, Any] | None:
    if value is None:
        return None
    parsed = json.loads(value)
    return parsed if isinstance(parsed, dict) else None


def _command_read(db: Session, command: ActuatorCommand) -> ActuatorCommandRead:
    actor = db.get(User, command.actor_user_id) if command.actor_user_id is not None else None
    return ActuatorCommandRead(
        command_id=command.command_id,
        tank_id=command.tank_id,
        device_id=command.device_id,
        actor_user_id=command.actor_user_id,
        actor_name=actor.name if actor else None,
        actuator=command.actuator,
        action=command.action,
        payload=json.loads(command.payload_json),
        status=command.status,
        requested_at=_explicit_utc(command.requested_at),
        expires_at=_explicit_utc(command.expires_at),
        executing_at=_explicit_utc(command.executing_at),
        execution_at=_explicit_utc(command.execution_at),
        result=_json_object(command.result_json),
        error=command.error_message,
    )


def _authenticate_device(
    x_device_key: str,
    request: Request,
    db: Session,
) -> RegisteredDevice:
    device = db.scalar(
        select(RegisteredDevice).where(
            RegisteredDevice.key_hash == hash_opaque_token(x_device_key),
        )
    )
    if device is None or not device.is_active:
        audit_event(db, request, "device.auth", "denied", target_type="device")
        db.commit()
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid device key")
    device.last_seen_at = utc_now()
    return device


def _resolve_device_for_tank(
    db: Session,
    tank_id: int,
    requested_device_id: str | None = None,
) -> RegisteredDevice:
    if db.get(Tank, tank_id) is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Tank not found")

    if requested_device_id:
        device = db.scalar(
            select(RegisteredDevice).where(
                RegisteredDevice.id == requested_device_id,
                RegisteredDevice.tank_id == tank_id,
                RegisteredDevice.is_active.is_(True),
            )
        )
        if device is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Active device is not registered to this tank")
        return device

    devices = list(
        db.scalars(
            select(RegisteredDevice)
            .where(RegisteredDevice.tank_id == tank_id, RegisteredDevice.is_active.is_(True))
            .order_by(RegisteredDevice.created_at, RegisteredDevice.id)
        ).all()
    )
    if not devices:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No active bridge device is registered to this tank")
    if len(devices) > 1:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Multiple active bridge devices are registered; specify device_id")
    return devices[0]


def _expire_queued_commands(db: Session, device_id: str, now: datetime, request: Request | None = None) -> None:
    expired = list(
        db.scalars(
            select(ActuatorCommand).where(
                ActuatorCommand.device_id == device_id,
                ActuatorCommand.status == "queued",
                ActuatorCommand.expires_at <= now,
            )
        ).all()
    )
    for command in expired:
        command.status = "expired"
        command.execution_at = now
        command.error_message = "Command expired before execution"
        audit_event(
            db,
            request,
            "actuator.command.expired",
            "success",
            target_type="actuator_command",
            target_id=command.command_id,
            details={"device_id": command.device_id, "tank_id": command.tank_id},
        )


def _device_is_online(device: RegisteredDevice, now: datetime | None = None) -> bool:
    last_seen = _explicit_utc(device.last_seen_at)
    if last_seen is None:
        return False
    return (now or utc_now()) - last_seen <= timedelta(seconds=DEVICE_ONLINE_WINDOW_SECONDS)


def _device_status(device: RegisteredDevice, now: datetime | None = None) -> str:
    if not device.is_active:
        return "disabled"
    return "online" if _device_is_online(device, now) else "offline"


def _device_read(db: Session, device: RegisteredDevice, now: datetime | None = None) -> DeviceRead:
    tank = db.get(Tank, device.tank_id)
    return DeviceRead(
        device_id=device.id,
        tank_id=device.tank_id,
        tank_name=tank.name if tank else "Unknown tank",
        is_active=device.is_active,
        created_at=_explicit_utc(device.created_at),
        last_seen_at=_explicit_utc(device.last_seen_at),
        status=_device_status(device, now),
    )


@router.post("/devices", response_model=DeviceProvisioned, status_code=status.HTTP_201_CREATED)
def register_device(
    payload: DeviceCreate,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
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
    audit_event(
        db,
        request,
        "device.register",
        "success",
        actor_user_id=current_user.id,
        target_type="device",
        target_id=device.id,
        details={"tank_id": device.tank_id},
    )
    db.commit()
    return DeviceProvisioned(device_id=device.id, tank_id=device.tank_id, device_key=raw_key)


@router.get("/devices", response_model=list[DeviceRead])
def list_devices(
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    now = utc_now()
    devices = db.scalars(select(RegisteredDevice).order_by(RegisteredDevice.id)).all()
    return [_device_read(db, device, now) for device in devices]


@router.get("/devices/{device_id}", response_model=DeviceRead)
def get_device(
    device_id: str,
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    device = db.get(RegisteredDevice, device_id)
    if device is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Device not found")
    return _device_read(db, device, utc_now())


@router.patch("/devices/{device_id}", response_model=DeviceRead)
def update_device(
    device_id: str,
    payload: DeviceUpdate,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    device = db.get(RegisteredDevice, device_id)
    if device is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Device not found")
    device.is_active = payload.is_active
    event_type = "device.activate" if payload.is_active else "device.deactivate"
    audit_event(
        db,
        request,
        event_type,
        "success",
        actor_user_id=current_user.id,
        target_type="device",
        target_id=device.id,
        details={"tank_id": device.tank_id},
    )
    db.commit()
    db.refresh(device)
    return _device_read(db, device, utc_now())


@router.post("/devices/{device_id}/rotate-key", response_model=DeviceKeyRotated)
def rotate_device_key(
    device_id: str,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    device = db.get(RegisteredDevice, device_id)
    if device is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Device not found")
    raw_key = opaque_token()
    device.key_hash = hash_opaque_token(raw_key)
    rotated_at = utc_now()
    audit_event(
        db,
        request,
        "device.key_rotate",
        "success",
        actor_user_id=current_user.id,
        target_type="device",
        target_id=device.id,
        details={"tank_id": device.tank_id},
    )
    db.commit()
    return DeviceKeyRotated(
        device_id=device.id,
        tank_id=device.tank_id,
        device_key=raw_key,
        rotated_at=rotated_at,
    )


@router.post("/device-ingestion/readings", response_model=SensorReadingRead, status_code=status.HTTP_201_CREATED)
def ingest_device_reading(
    payload: DeviceReadingCreate,
    request: Request,
    x_device_key: str = Header(...),
    db: Session = Depends(get_db),
):
    device = _authenticate_device(x_device_key, request, db)
    values = payload.model_dump(exclude={"observed_at"})
    values.update({"dissolved_oxygen": None, "ammonia": None, "is_mock": False})
    if payload.observed_at is not None:
        observed_at = payload.observed_at
        values["timestamp"] = observed_at.replace(tzinfo=timezone.utc) if observed_at.tzinfo is None else observed_at
    reading = ingest_reading(db, device.tank_id, values, device_id=device.id)
    audit_event(
        db,
        request,
        "device.ingest",
        "success",
        target_type="device",
        target_id=device.id,
        details={"tank_id": device.tank_id, "reading_id": reading.id},
    )
    db.commit()
    db.refresh(reading)
    return reading


@router.post("/tanks/{tank_id}/actuators/commands", response_model=ActuatorCommandRead, status_code=status.HTTP_201_CREATED)
def queue_actuator_command(
    tank_id: int,
    payload: ActuatorCommandCreate,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    device = _resolve_device_for_tank(db, tank_id, payload.device_id)
    requested_at = utc_now()
    if payload.actuator in PUMP_ACTUATORS and not _device_is_online(device, requested_at):
        audit_event(
            db,
            request,
            "actuator.command.rejected_offline",
            "denied",
            actor_user_id=current_user.id,
            target_type="device",
            target_id=device.id,
            details={"tank_id": tank_id, "actuator": payload.actuator, "action": payload.action},
        )
        db.commit()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Bridge is offline; pump manual-test commands were not queued",
        )
    command = ActuatorCommand(
        command_id=str(uuid.uuid4()),
        device_id=device.id,
        tank_id=tank_id,
        actor_user_id=current_user.id,
        actuator=payload.actuator,
        action=payload.action,
        payload_json=json.dumps(payload.payload, separators=(",", ":"), sort_keys=True),
        status="queued",
        requested_at=requested_at,
        expires_at=requested_at + timedelta(seconds=payload.expires_in_seconds or COMMAND_EXPIRY_DEFAULT_SECONDS),
    )
    db.add(command)
    db.flush()
    audit_event(
        db,
        request,
        "actuator.command.queued",
        "success",
        actor_user_id=current_user.id,
        target_type="actuator_command",
        target_id=command.command_id,
        details={
            "tank_id": tank_id,
            "device_id": device.id,
            "actuator": command.actuator,
            "action": command.action,
            "payload": payload.payload,
            "expires_at": command.expires_at.isoformat(),
        },
    )
    db.commit()
    db.refresh(command)
    return _command_read(db, command)


def _actuator_status_for_device(db: Session, device: RegisteredDevice) -> DeviceActuatorStatusRead:
    now = utc_now()
    last_seen = _explicit_utc(device.last_seen_at)
    if last_seen is None:
        freshness = "unknown"
        online = False
    else:
        online = _device_is_online(device, now)
        freshness = "online" if online else "offline"
    states = {
        state.actuator: state
        for state in db.scalars(
            select(ActuatorState).where(ActuatorState.device_id == device.id)
        ).all()
    }
    return DeviceActuatorStatusRead(
        tank_id=device.tank_id,
        device_id=device.id,
        device_online=online,
        device_freshness=freshness,
        last_seen_at=last_seen,
        checked_at=now,
        actuators=[
            ActuatorStateRead(
                actuator=actuator,
                state=json.loads(states[actuator].state_json) if actuator in states else None,
                refreshed_at=_explicit_utc(states[actuator].refreshed_at) if actuator in states else None,
            )
            for actuator in ACTUATORS
        ],
    )


@router.get("/tanks/{tank_id}/actuators/status", response_model=DeviceActuatorStatusRead)
def get_actuator_status(
    tank_id: int,
    request: Request,
    device_id: str | None = Query(default=None),
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    device = _resolve_device_for_tank(db, tank_id, device_id)
    _expire_queued_commands(db, device.id, utc_now(), request)
    db.commit()
    return _actuator_status_for_device(db, device)


@router.get("/tanks/{tank_id}/actuators/history", response_model=ActuatorCommandHistoryPage)
def get_actuator_history(
    tank_id: int,
    request: Request,
    device_id: str | None = Query(default=None),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=10, ge=1, le=50),
    actuator: ActuatorName | None = Query(default=None),
    command_status: CommandStatus | None = Query(default=None, alias="status"),
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    device = _resolve_device_for_tank(db, tank_id, device_id)
    _expire_queued_commands(db, device.id, utc_now(), request)
    filters = (ActuatorCommand.device_id == device.id, ActuatorCommand.tank_id == tank_id)
    base_filters = filters
    if actuator is not None:
        filters += (ActuatorCommand.actuator == actuator,)
    if command_status is not None:
        filters += (ActuatorCommand.status == command_status,)
    total = db.scalar(select(func.count()).select_from(ActuatorCommand).where(*filters)) or 0
    summary_rows = db.execute(
        select(ActuatorCommand.status, func.count())
        .where(*base_filters)
        .group_by(ActuatorCommand.status)
    ).all()
    summary_counts = {status_value: count for status_value, count in summary_rows}
    summary = ActuatorHistorySummary(
        total=sum(summary_counts.values()),
        queued=summary_counts.get("queued", 0),
        executing=summary_counts.get("executing", 0),
        succeeded=summary_counts.get("succeeded", 0),
        failed=summary_counts.get("failed", 0),
        expired=summary_counts.get("expired", 0),
    )
    commands = list(
        db.scalars(
            select(ActuatorCommand)
            .where(*filters)
            .order_by(ActuatorCommand.requested_at.desc())
            .offset((page - 1) * page_size)
            .limit(page_size)
        ).all()
    )
    db.commit()
    total_pages = (total + page_size - 1) // page_size
    return ActuatorCommandHistoryPage(
        items=[_command_read(db, command) for command in commands],
        page=page,
        page_size=page_size,
        total=total,
        total_pages=total_pages,
        has_previous=page > 1,
        has_next=page < total_pages,
        summary=summary,
    )


@router.get("/device-ingestion/actuators/pending", response_model=list[PendingActuatorCommand])
def get_pending_actuator_commands(
    request: Request,
    x_device_key: str = Header(...),
    limit: int = Query(default=20, ge=1, le=50),
    db: Session = Depends(get_db),
):
    device = _authenticate_device(x_device_key, request, db)
    now = utc_now()
    _expire_queued_commands(db, device.id, now, request)
    commands = list(
        db.scalars(
            select(ActuatorCommand)
            .where(
                ActuatorCommand.device_id == device.id,
                ActuatorCommand.status == "queued",
                ActuatorCommand.expires_at > now,
            )
            .order_by(ActuatorCommand.requested_at, ActuatorCommand.command_id)
            .limit(limit)
        ).all()
    )
    db.commit()
    return [
        PendingActuatorCommand(
            command_id=command.command_id,
            device_id=command.device_id,
            actuator=command.actuator,
            action=command.action,
            payload=json.loads(command.payload_json),
            requested_at=_explicit_utc(command.requested_at),
            expires_at=_explicit_utc(command.expires_at),
        )
        for command in commands
    ]


def _get_device_command(db: Session, device: RegisteredDevice, command_id: str) -> ActuatorCommand:
    command = db.scalar(
        select(ActuatorCommand).where(
            ActuatorCommand.command_id == command_id,
            ActuatorCommand.device_id == device.id,
            ActuatorCommand.tank_id == device.tank_id,
        )
    )
    if command is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Actuator command not found")
    return command


@router.post("/device-ingestion/actuators/{command_id}/executing", response_model=ActuatorCommandRead)
def mark_actuator_command_executing(
    command_id: str,
    request: Request,
    x_device_key: str = Header(...),
    db: Session = Depends(get_db),
):
    device = _authenticate_device(x_device_key, request, db)
    command = _get_device_command(db, device, command_id)
    now = utc_now()
    if command.status == "queued":
        claimed = db.execute(
            update(ActuatorCommand)
            .where(
                ActuatorCommand.command_id == command_id,
                ActuatorCommand.device_id == device.id,
                ActuatorCommand.status == "queued",
                ActuatorCommand.expires_at > now,
            )
            .values(status="executing", executing_at=now)
            .execution_options(synchronize_session=False)
        ).rowcount
        db.expire(command)
        db.refresh(command)
        if claimed != 1:
            if command.status == "queued" and _explicit_utc(command.expires_at) <= now:
                command.status = "expired"
                command.execution_at = now
                command.error_message = "Command expired before execution"
                audit_event(db, request, "actuator.command.expired", "success", target_type="actuator_command", target_id=command.command_id)
                db.commit()
                raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Actuator command has expired")
            db.commit()
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=f"Actuator command is already {command.status}")
        audit_event(
            db,
            request,
            "actuator.command.executing",
            "success",
            target_type="actuator_command",
            target_id=command.command_id,
            details={"device_id": device.id, "tank_id": device.tank_id},
        )
    elif command.status == "executing":
        db.commit()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Actuator command is already executing")
    else:
        db.commit()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=f"Actuator command is already {command.status}")
    db.commit()
    db.refresh(command)
    return _command_read(db, command)


@router.post("/device-ingestion/actuators/{command_id}/succeeded", response_model=ActuatorCommandRead)
def mark_actuator_command_succeeded(
    command_id: str,
    payload: ActuatorCommandResult,
    request: Request,
    x_device_key: str = Header(...),
    db: Session = Depends(get_db),
):
    device = _authenticate_device(x_device_key, request, db)
    command = _get_device_command(db, device, command_id)
    existing_result = _json_object(command.result_json)
    if command.status == "succeeded":
        if existing_result == payload.result:
            db.commit()
            return _command_read(db, command)
        db.commit()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Command already succeeded with a different result")
    if command.status != "executing":
        db.commit()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=f"Cannot succeed command in {command.status} state")
    command.status = "succeeded"
    command.execution_at = utc_now()
    command.result_json = json.dumps(payload.result, separators=(",", ":"), sort_keys=True)
    command.error_message = None
    audit_event(
        db,
        request,
        "actuator.command.succeeded",
        "success",
        target_type="actuator_command",
        target_id=command.command_id,
        details={"device_id": device.id, "tank_id": device.tank_id},
    )
    db.commit()
    db.refresh(command)
    return _command_read(db, command)


@router.post("/device-ingestion/actuators/{command_id}/failed", response_model=ActuatorCommandRead)
def mark_actuator_command_failed(
    command_id: str,
    payload: ActuatorCommandFailure,
    request: Request,
    x_device_key: str = Header(...),
    db: Session = Depends(get_db),
):
    device = _authenticate_device(x_device_key, request, db)
    command = _get_device_command(db, device, command_id)
    if command.status == "failed":
        if command.error_message == payload.error:
            db.commit()
            return _command_read(db, command)
        db.commit()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Command already failed with a different error")
    if command.status != "executing":
        db.commit()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=f"Cannot fail command in {command.status} state")
    command.status = "failed"
    command.execution_at = utc_now()
    command.result_json = json.dumps(payload.result, separators=(",", ":"), sort_keys=True) if payload.result else None
    command.error_message = payload.error
    audit_event(
        db,
        request,
        "actuator.command.failed",
        "success",
        target_type="actuator_command",
        target_id=command.command_id,
        details={"device_id": device.id, "tank_id": device.tank_id, "error": payload.error},
    )
    db.commit()
    db.refresh(command)
    return _command_read(db, command)


@router.post("/device-ingestion/actuator-state", response_model=ActuatorStateRead)
def report_actuator_state(
    payload: ActuatorStateReport,
    request: Request,
    x_device_key: str = Header(...),
    db: Session = Depends(get_db),
):
    device = _authenticate_device(x_device_key, request, db)
    if payload.device_id is not None and payload.device_id != device.id:
        db.commit()
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="State device does not match the authenticated device")
    if payload.command_id is not None:
        command = _get_device_command(db, device, payload.command_id)
        if command.actuator != payload.actuator:
            db.commit()
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="State actuator does not match the command")

    refreshed_at = utc_now()
    state_json = json.dumps(payload.state, separators=(",", ":"), sort_keys=True)
    current = db.scalar(
        select(ActuatorState).where(
            ActuatorState.device_id == device.id,
            ActuatorState.actuator == payload.actuator,
        )
    )
    if current is None:
        current = ActuatorState(
            device_id=device.id,
            tank_id=device.tank_id,
            actuator=payload.actuator,
            state_json=state_json,
            refreshed_at=refreshed_at,
        )
        db.add(current)
    else:
        current.tank_id = device.tank_id
        current.state_json = state_json
        current.refreshed_at = refreshed_at
    db.add(
        ActuatorStateHistory(
            device_id=device.id,
            tank_id=device.tank_id,
            actuator=payload.actuator,
            command_id=payload.command_id,
            state_json=state_json,
            reported_at=refreshed_at,
        )
    )
    audit_event(
        db,
        request,
        "device.actuator_state",
        "success",
        target_type="device",
        target_id=device.id,
        details={"tank_id": device.tank_id, "actuator": payload.actuator, "command_id": payload.command_id},
    )
    db.commit()
    db.refresh(current)
    return ActuatorStateRead(
        actuator=current.actuator,
        state=json.loads(current.state_json),
        refreshed_at=_explicit_utc(current.refreshed_at),
    )

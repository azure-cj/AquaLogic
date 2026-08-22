"""Central tank lifecycle guards and monitoring-expectation transitions."""

from __future__ import annotations

from datetime import datetime

from fastapi import HTTPException, status
from sqlalchemy import func, select, text
from sqlalchemy.orm import Session

from app.models import ActuatorCommand, RegisteredDevice, Tank
from app.security import utc_now


RETIRED_TANK_DETAIL = "Tank is retired and read-only"
ACTIVE_TANK_REQUIRED_DETAIL = "Tank must be active for this operation"
RETIREMENT_BLOCKED_BY_ACTUATOR_DETAIL = (
    "Tank cannot be retired while actuator work is executing or has an uncleared unknown outcome"
)


def tank_or_404(db: Session, tank_id: int) -> Tank:
    tank = db.get(Tank, tank_id)
    if tank is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Tank not found")
    return tank


def require_active_tank(tank: Tank, db: Session | None = None) -> Tank:
    if tank.retired_at is not None:
        if db is not None:
            db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=RETIRED_TANK_DETAIL)
    return tank


def require_active_tank_by_id(db: Session, tank_id: int) -> Tank:
    return require_active_tank(tank_or_404(db, tank_id))


def lock_tank_for_mutation(db: Session, tank_id: int) -> Tank:
    """Serialize lifecycle-sensitive writes on SQLite and PostgreSQL."""

    bind = db.get_bind()
    if bind.dialect.name == "sqlite":
        # Route reads can begin a deferred transaction before this helper is
        # called. End that read before taking SQLite's coarse writer lock.
        db.commit()
        db.execute(text("BEGIN IMMEDIATE"))
        return tank_or_404(db, tank_id)
    tank = db.scalar(select(Tank).where(Tank.id == tank_id).with_for_update())
    if tank is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Tank not found")
    return tank


def lock_tank_and_device(db: Session, tank_id: int, device_id: str) -> tuple[Tank, RegisteredDevice]:
    """Lock the tank before its device so retirement and device writes order consistently."""

    tank = lock_tank_for_mutation(db, tank_id)
    if db.get_bind().dialect.name == "sqlite":
        device = db.get(RegisteredDevice, device_id)
    else:
        device = db.scalar(
            select(RegisteredDevice)
            .where(RegisteredDevice.id == device_id, RegisteredDevice.tank_id == tank_id)
            .with_for_update()
        )
    if device is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Device not found")
    if device.tank_id != tank_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Device is not registered to this tank")
    return tank, device


def active_device_count(db: Session, tank_id: int) -> int:
    return int(
        db.scalar(
            select(func.count())
            .select_from(RegisteredDevice)
            .where(RegisteredDevice.tank_id == tank_id, RegisteredDevice.is_active.is_(True))
        )
        or 0
    )


def refresh_monitoring_expectation(
    db: Session,
    tank: Tank,
    *,
    now: datetime | None = None,
) -> None:
    """Maintain the explicit zero-to-one/one-to-zero expectation boundary.

    The packet-09 detector consumes this timestamp. Retirement always clears it
    and resolves any active incident through the dedicated lifecycle boundary.
    """

    current_time = now or utc_now()
    db.flush()
    if tank.retired_at is not None or active_device_count(db, tank.id) == 0:
        tank.monitoring_expected_at = None
        if tank.retired_at is None:
            from app.services.monitoring_incidents import resolve_active_monitoring_incident

            resolve_active_monitoring_incident(
                db,
                tank.id,
                reason="monitoring_disabled",
                resolved_at=current_time,
            )
    elif tank.monitoring_expected_at is None:
        tank.monitoring_expected_at = current_time


def uncleared_actuator_work(db: Session, tank_id: int) -> ActuatorCommand | None:
    return db.scalar(
        select(ActuatorCommand)
        .where(
            ActuatorCommand.tank_id == tank_id,
            (
                (ActuatorCommand.status == "executing")
                | (
                    (ActuatorCommand.status == "outcome_unknown")
                    & ActuatorCommand.physical_verification_at.is_(None)
                )
            ),
        )
        .order_by(ActuatorCommand.requested_at, ActuatorCommand.command_id)
        .limit(1)
    )


def active_tank_filters(column=Tank.retired_at):
    return column.is_(None)

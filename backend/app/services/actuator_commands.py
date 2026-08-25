"""Shared lifecycle and concurrency rules for physical actuator commands."""

from __future__ import annotations

from datetime import datetime, timedelta

from fastapi import Request
from sqlalchemy import select, text, update
from sqlalchemy.orm import Session

from app.models import ActuatorCommand, RegisteredDevice
from app.security import utc_now
from app.services.auth_security import audit_event


# The bridge permits a pump completion wait of up to 120 seconds. Five-second
# ESP32/backend requests, the possible one-shot safety stop, and scheduling /
# network margin are deliberately covered by this larger server-side window.
# This is confirmation time after claim, not queue time before claim.
ACTUATOR_CONFIRMATION_WINDOW_SECONDS = 180
ACTUATOR_CONFIRMATION_WINDOW = timedelta(seconds=ACTUATOR_CONFIRMATION_WINDOW_SECONDS)
UNKNOWN_OUTCOME_MESSAGE = "Confirmation deadline elapsed; physical outcome is unknown"
PUMP_ACTUATORS = {"pump_a", "pump_b"}


def confirmation_deadline(executing_at: datetime) -> datetime:
    return executing_at + ACTUATOR_CONFIRMATION_WINDOW


def mark_actuator_command_outcome_unknown(
    db: Session,
    command: ActuatorCommand,
    *,
    now: datetime,
    request: Request | None = None,
    error_message: str = UNKNOWN_OUTCOME_MESSAGE,
    result_json: str | None = None,
) -> bool:
    """Conditionally finalize one executing command as outcome_unknown.

    Both the autonomous reconciler and the bridge's explicit uncertainty
    report use this single transition path. The conditional status predicate
    makes concurrent callers idempotent and keeps the audit event one-shot.
    """

    changed = db.execute(
        update(ActuatorCommand)
        .where(
            ActuatorCommand.command_id == command.command_id,
            ActuatorCommand.status == "executing",
        )
        .values(
            status="outcome_unknown",
            outcome_unknown_at=now,
            error_message=error_message[:500],
            result_json=result_json,
        )
        .execution_options(synchronize_session=False)
    ).rowcount
    if changed != 1:
        return False
    db.expire(command)
    db.refresh(command)
    audit_event(
        db,
        request,
        "actuator.command.outcome_unknown",
        "success",
        target_type="actuator_command",
        target_id=command.command_id,
        details={
            "device_id": command.device_id,
            "tank_id": command.tank_id,
            "actuator": command.actuator,
            "action": command.action,
            "executing_at": command.executing_at.isoformat() if command.executing_at else None,
            "confirmation_deadline_at": (
                command.confirmation_deadline_at.isoformat()
                if command.confirmation_deadline_at
                else confirmation_deadline(command.executing_at).isoformat()
                if command.executing_at
                else None
            ),
        },
    )
    return True


def reconcile_actuator_commands(
    db: Session,
    device_id: str,
    *,
    now: datetime | None = None,
    request: Request | None = None,
) -> int:
    """Finalize overdue executing commands as unknown exactly once.

    Callers own the surrounding transaction. Only rows still in ``executing``
    are eligible, so repeated calls are safe and cannot add duplicate audit
    transitions after the terminal state has been persisted.
    """

    current_time = now or utc_now()
    fallback_deadline = current_time - ACTUATOR_CONFIRMATION_WINDOW
    bind = db.get_bind()
    if bind.dialect.name == "sqlite":
        # Reconciliation can be entered from a read-first status/history path.
        # Take SQLite's writer lock before selecting candidates so a second
        # development worker cannot observe the same executing row and emit a
        # duplicate transition audit.
        if db.in_transaction():
            db.commit()
        db.execute(text("BEGIN IMMEDIATE"))
        lock_candidates = False
    else:
        # PostgreSQL workers serialize candidate reads at the command row.
        lock_candidates = True
    candidate_query = select(ActuatorCommand).where(
        ActuatorCommand.device_id == device_id,
        ActuatorCommand.status == "executing",
        ActuatorCommand.executing_at.is_not(None),
        (
            (ActuatorCommand.confirmation_deadline_at <= current_time)
            | (
                ActuatorCommand.confirmation_deadline_at.is_(None)
                & (ActuatorCommand.executing_at <= fallback_deadline)
            )
        ),
    )
    if lock_candidates:
        candidate_query = candidate_query.with_for_update(nowait=False, skip_locked=False)
    commands = list(db.scalars(candidate_query).all())
    transitioned = 0
    for command in commands:
        transitioned += int(
            mark_actuator_command_outcome_unknown(
                db,
                command,
                now=current_time,
                request=request,
            )
        )
    return transitioned


def serialize_pump_mutation(db: Session, device: RegisteredDevice) -> None:
    """Serialize pump queue/claim checks for both supported databases.

    PostgreSQL locks the registered-device row until the caller commits. SQLite
    has no row-level ``FOR UPDATE`` equivalent, so the development database
    takes its coarse writer lock with ``BEGIN IMMEDIATE``. The caller must do
    the active-command check and write in the same transaction.
    """

    bind = db.get_bind()
    if bind.dialect.name == "sqlite":
        # Route helpers may have started a deferred read transaction while
        # resolving the device. Commit that read before taking the writer lock.
        db.commit()
        db.execute(text("BEGIN IMMEDIATE"))
        return
    db.execute(
        select(RegisteredDevice.id)
        .where(RegisteredDevice.id == device.id)
        .with_for_update()
    ).scalar_one()


def active_pump_dispense(
    db: Session,
    *,
    device_id: str,
    actuator: str,
    exclude_command_id: str | None = None,
) -> ActuatorCommand | None:
    """Return an uncleared same-device/same-pump dispense lock, if present."""

    filters = (
        ActuatorCommand.device_id == device_id,
        ActuatorCommand.actuator == actuator,
        ActuatorCommand.action == "dispense",
        ActuatorCommand.status.in_(["executing", "outcome_unknown"]),
        (
            ActuatorCommand.status == "executing"
        )
        | (
            (ActuatorCommand.status == "outcome_unknown")
            & ActuatorCommand.physical_verification_at.is_(None)
        ),
    )
    if exclude_command_id is not None:
        filters += (ActuatorCommand.command_id != exclude_command_id,)
    return db.scalar(
        select(ActuatorCommand)
        .where(*filters)
        .order_by(ActuatorCommand.requested_at, ActuatorCommand.command_id)
        .limit(1)
    )


def reconcile_all_actuator_commands(
    db: Session,
    *,
    now: datetime | None = None,
    request: Request | None = None,
) -> int:
    """Reconcile every overdue executing command for unattended maintenance."""

    device_ids = list(
        db.scalars(
            select(ActuatorCommand.device_id)
            .where(ActuatorCommand.status == "executing")
            .distinct()
            .order_by(ActuatorCommand.device_id)
        ).all()
    )
    return sum(
        reconcile_actuator_commands(db, device_id, now=now, request=request)
        for device_id in device_ids
    )

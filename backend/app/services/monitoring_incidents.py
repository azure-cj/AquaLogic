"""Persistent tank-level monitoring outage detection and recovery."""

from __future__ import annotations

import logging
import threading
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from sqlalchemy import exists, select, text, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.config import settings
from app.database import SessionLocal
from app.models import MonitoringIncident, RegisteredDevice, SensorReading, Tank
from app.services.auth_security import audit_event
from app.services.actuator_commands import reconcile_all_actuator_commands
from app.services.push_notifications import enqueue_push_notification
from app.security import utc_now


logger = logging.getLogger(__name__)


def _aware(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def resolve_active_monitoring_incident(
    db: Session,
    tank_id: int,
    *,
    reason: str,
    resolved_at: datetime | None = None,
    recovery_reading: SensorReading | None = None,
) -> MonitoringIncident | None:
    """Resolve one active incident exactly once inside the caller transaction."""

    if reason not in {"reporting_recovered", "monitoring_disabled", "tank_retired"}:
        raise ValueError(f"Unsupported monitoring incident resolution reason: {reason}")
    incident = db.scalar(
        select(MonitoringIncident)
        .where(MonitoringIncident.tank_id == tank_id, MonitoringIncident.resolved_at.is_(None))
        .order_by(MonitoringIncident.id)
        .with_for_update()
    )
    if incident is None:
        return None

    resolved_value = _aware(resolved_at) or utc_now()
    result = db.execute(
        update(MonitoringIncident)
        .where(
            MonitoringIncident.id == incident.id,
            MonitoringIncident.resolved_at.is_(None),
        )
        .values(
            resolved_at=resolved_value,
            resolution_reason=reason,
            recovery_reading_id=recovery_reading.id if recovery_reading is not None else None,
        )
    )
    if result.rowcount != 1:
        return None

    audit_event(
        db,
        None,
        "monitoring_incident.resolve",
        "success",
        target_type="monitoring_incident",
        target_id=incident.id,
        details={
            "tank_id": tank_id,
            "reason": reason,
            "recovery_reading_id": recovery_reading.id if recovery_reading is not None else None,
        },
    )
    db.flush()
    db.refresh(incident)
    if reason == "reporting_recovered":
        enqueue_push_notification(
            db,
            event_type="monitoring_recovered",
            source_id=incident.id,
            tank_id=incident.tank_id,
            title="Monitoring restored",
            body="A tank has resumed reporting. Open AquaLogic for details.",
            now=resolved_value,
        )
    return incident


@dataclass(frozen=True)
class DetectorResult:
    eligible_tanks: int
    created_incidents: int


@dataclass(frozen=True)
class MaintenanceResult:
    actuator_unknown_transitions: int
    monitoring: DetectorResult | None


def _begin_detector_transaction(db: Session) -> None:
    """Serialize SQLite detector/lifecycle writers; PostgreSQL uses row locks."""

    if db.get_bind().dialect.name == "sqlite":
        if db.in_transaction():
            db.commit()
        db.execute(text("BEGIN IMMEDIATE"))


def detect_monitoring_incidents(
    db: Session,
    *,
    evaluated_at: datetime | None = None,
    grace_seconds: int | None = None,
) -> DetectorResult:
    """Create overdue tank incidents once and commit one predictable cycle."""

    now = _aware(evaluated_at) or utc_now()
    grace = settings.monitoring_outage_grace_seconds if grace_seconds is None else grace_seconds
    if grace <= 90:
        raise ValueError("Monitoring incident grace must be strictly greater than 90 seconds")

    _begin_detector_transaction(db)
    try:
        candidate_ids = list(
            db.scalars(
                select(Tank.id)
                .where(
                    Tank.retired_at.is_(None),
                    Tank.monitoring_expected_at.is_not(None),
                    exists(
                        select(1).where(
                            RegisteredDevice.tank_id == Tank.id,
                            RegisteredDevice.is_active.is_(True),
                        )
                    ),
                )
                .order_by(Tank.id)
            ).all()
        )
        created = 0
        eligible = 0
        for tank_id in candidate_ids:
            tank_stmt = select(Tank).where(Tank.id == tank_id)
            if db.get_bind().dialect.name != "sqlite":
                tank_stmt = tank_stmt.with_for_update()
            tank = db.scalar(tank_stmt)
            if tank is None or tank.retired_at is not None or tank.monitoring_expected_at is None:
                continue

            active_device_exists = db.scalar(
                select(exists().where(
                    RegisteredDevice.tank_id == tank.id,
                    RegisteredDevice.is_active.is_(True),
                ))
            )
            if not active_device_exists:
                tank.monitoring_expected_at = None
                resolve_active_monitoring_incident(
                    db,
                    tank.id,
                    reason="monitoring_disabled",
                    resolved_at=now,
                )
                continue

            eligible += 1
            latest = db.scalar(
                select(SensorReading)
                .where(SensorReading.tank_id == tank.id)
                .order_by(SensorReading.received_at.desc(), SensorReading.id.desc())
                .limit(1)
            )
            expected_at = _aware(tank.monitoring_expected_at)
            latest_received_at = _aware(latest.received_at) if latest else None
            baseline = max(value for value in (expected_at, latest_received_at) if value is not None)
            if now < baseline + timedelta(seconds=grace):
                continue
            if db.scalar(
                select(MonitoringIncident.id).where(
                    MonitoringIncident.tank_id == tank.id,
                    MonitoringIncident.resolved_at.is_(None),
                )
            ) is not None:
                continue

            incident = MonitoringIncident(
                tank_id=tank.id,
                started_at=baseline,
                detected_at=now,
                last_reading_received_at=latest_received_at,
            )
            try:
                with db.begin_nested():
                    db.add(incident)
                    db.flush()
                    audit_event(
                        db,
                        None,
                        "monitoring_incident.open",
                        "success",
                        target_type="monitoring_incident",
                        target_id=incident.id,
                        details={
                            "tank_id": tank.id,
                            "started_at": baseline.isoformat(),
                            "detected_at": now.isoformat(),
                            "last_reading_received_at": latest_received_at.isoformat()
                            if latest_received_at
                            else None,
                        },
                    )
                    enqueue_push_notification(
                        db,
                        event_type="monitoring_incident",
                        source_id=incident.id,
                        tank_id=tank.id,
                        title="Monitoring outage",
                        body="A tank has stopped reporting. Open AquaLogic for details.",
                        now=now,
                    )
                created += 1
            except IntegrityError:
                # Another worker won the portable partial-unique-index race.
                continue
        db.commit()
        return DetectorResult(eligible_tanks=eligible, created_incidents=created)
    except Exception:
        db.rollback()
        raise


def run_periodic_maintenance(*, evaluated_at: datetime | None = None) -> MaintenanceResult:
    """Run unattended actuator reconciliation and monitoring detection together."""

    now = _aware(evaluated_at) or utc_now()
    with SessionLocal() as db:
        actuator_unknown_transitions = reconcile_all_actuator_commands(db, now=now)
        monitoring = (
            detect_monitoring_incidents(db, evaluated_at=now)
            if settings.monitoring_incidents_enabled
            else None
        )
        if monitoring is None:
            db.commit()
        return MaintenanceResult(
            actuator_unknown_transitions=actuator_unknown_transitions,
            monitoring=monitoring,
        )


@dataclass
class PeriodicMaintenanceHandle:
    stop_event: threading.Event
    thread: threading.Thread

    def stop(self) -> None:
        self.stop_event.set()
        self.thread.join(timeout=max(1, settings.monitoring_incident_check_interval_seconds + 1))


def start_periodic_maintenance() -> PeriodicMaintenanceHandle:
    """Start one process-local loop for unattended safety maintenance."""

    stop_event = threading.Event()

    def _loop() -> None:
        while not stop_event.is_set():
            try:
                result = run_periodic_maintenance(evaluated_at=utc_now())
                if result.actuator_unknown_transitions:
                    logger.info(
                        "Actuator maintenance reconciled %s unknown outcome(s)",
                        result.actuator_unknown_transitions,
                    )
                if result.monitoring and result.monitoring.created_incidents:
                    logger.info(
                        "Monitoring incident detector recorded %s tank outage(s)",
                        result.monitoring.created_incidents,
                    )
            except Exception:
                logger.exception("Periodic maintenance cycle failed")
            stop_event.wait(settings.monitoring_incident_check_interval_seconds)

    thread = threading.Thread(target=_loop, name="aqualogic-periodic-maintenance", daemon=True)
    thread.start()
    return PeriodicMaintenanceHandle(stop_event=stop_event, thread=thread)


def start_monitoring_incident_detector() -> PeriodicMaintenanceHandle | None:
    """Compatibility wrapper for callers that only enable incident detection."""

    if not settings.monitoring_incidents_enabled:
        return None
    return start_periodic_maintenance()

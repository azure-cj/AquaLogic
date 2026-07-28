"""Single ingestion and status-evaluation path for sensor data."""
from datetime import datetime, timezone
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Alert, AlertSeverity, SensorReading, ThresholdConfig, ThresholdRevision
from app.services.reading_freshness import is_reading_current

PARAMETERS = ("temperature", "ph", "turbidity", "dissolved_oxygen", "tds", "ammonia")
DEFAULT_THRESHOLDS = {
    "temperature": ("°C", 20, 28, 18, 30), "ph": ("pH", 6.5, 7.8, 6.0, 8.5),
    "turbidity": ("NTU", None, 8, None, 15), "dissolved_oxygen": ("mg/L", 5, None, 3, None),
    "tds": ("ppm", 50, 400, 20, 550), "ammonia": ("ppm", None, 0.25, None, 0.5),
}


def ensure_default_thresholds(db: Session) -> None:
    for parameter, values in DEFAULT_THRESHOLDS.items():
        if not db.scalar(select(ThresholdConfig).where(ThresholdConfig.parameter == parameter)):
            unit, warning_min, warning_max, critical_min, critical_max = values
            db.add(ThresholdConfig(parameter=parameter, unit=unit, warning_min=warning_min, warning_max=warning_max, critical_min=critical_min, critical_max=critical_max))
    db.flush()
    earliest = db.scalar(select(SensorReading.timestamp).order_by(SensorReading.timestamp).limit(1))
    effective_from = earliest or datetime.now(timezone.utc)
    for threshold in db.scalars(select(ThresholdConfig)).all():
        exists = db.scalar(
            select(ThresholdRevision.id)
            .where(ThresholdRevision.parameter == threshold.parameter)
            .limit(1)
        )
        if exists is None:
            db.add(
                ThresholdRevision(
                    parameter=threshold.parameter,
                    unit=threshold.unit,
                    warning_min=threshold.warning_min,
                    warning_max=threshold.warning_max,
                    critical_min=threshold.critical_min,
                    critical_max=threshold.critical_max,
                    enabled=threshold.enabled,
                    effective_from=effective_from,
                )
            )
    db.commit()


def _severity(value: float, threshold: ThresholdConfig) -> AlertSeverity | None:
    if not threshold.enabled:
        return None
    if ((threshold.critical_min is not None and value < threshold.critical_min) or (threshold.critical_max is not None and value > threshold.critical_max)):
        return AlertSeverity.critical
    if ((threshold.warning_min is not None and value < threshold.warning_min) or (threshold.warning_max is not None and value > threshold.warning_max)):
        return AlertSeverity.warning
    return None


def reading_violations(db: Session, reading: SensorReading) -> list[tuple[str, AlertSeverity]]:
    thresholds = {item.parameter: item for item in db.scalars(select(ThresholdConfig)).all()}
    return [(p, severity) for p in PARAMETERS if (threshold := thresholds.get(p)) and (severity := _severity(getattr(reading, p), threshold))]


def ingest_reading(db: Session, tank_id: int, values: dict) -> SensorReading:
    reading = SensorReading(tank_id=tank_id, **values)
    db.add(reading)
    db.flush()
    for parameter, severity in reading_violations(db, reading):
        alert = db.scalar(select(Alert).where(Alert.tank_id == tank_id, Alert.parameter == parameter, Alert.is_resolved.is_(False)))
        message = f"{parameter.replace('_', ' ').title()} is outside its {severity.value} threshold"
        if alert is None:
            db.add(Alert(tank_id=tank_id, reading_id=reading.id, parameter=parameter, severity=severity, message=message))
        elif severity == AlertSeverity.critical and alert.severity != AlertSeverity.critical:
            alert.severity, alert.reading_id, alert.message = severity, reading.id, message
    db.commit()
    db.refresh(reading)
    return reading


def status_for_reading(
    db: Session,
    reading: SensorReading | None,
    *,
    evaluated_at: datetime | None = None,
) -> str:
    if reading is None:
        return "offline"
    if not is_reading_current(reading.timestamp, evaluated_at=evaluated_at):
        return "offline"
    severities = [severity for _, severity in reading_violations(db, reading)]
    if AlertSeverity.critical in severities:
        return "critical"
    if AlertSeverity.warning in severities:
        return "warning"
    return "normal"


def parameter_statuses(
    db: Session,
    reading: SensorReading | None,
    *,
    evaluated_at: datetime | None = None,
) -> dict[str, str]:
    """Return visitor-safe status labels for every supported reading."""
    if reading is None:
        return {parameter: "unavailable" for parameter in PARAMETERS}

    if not is_reading_current(reading.timestamp, evaluated_at=evaluated_at):
        return {parameter: "offline" for parameter in PARAMETERS}

    thresholds = {
        item.parameter: item
        for item in db.scalars(select(ThresholdConfig)).all()
    }
    result: dict[str, str] = {}
    for parameter in PARAMETERS:
        threshold = thresholds.get(parameter)
        if threshold is None:
            result[parameter] = "normal"
            continue
        if not threshold.enabled:
            result[parameter] = "unavailable"
            continue
        severity = _severity(getattr(reading, parameter), threshold)
        result[parameter] = severity.value if severity else "normal"
    return result

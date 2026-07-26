from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session, selectinload
from app.database import get_db
from app.dependencies import require_admin, require_password_change_complete
from app.models import Alert, SensorReading, Tank, ThresholdConfig, User
from app.schemas.threshold import ThresholdRead, ThresholdUpdate
from app.services.decision_engine import status_for_reading

router = APIRouter(tags=["dashboard"])

@router.get("/fleet")
def fleet(db: Session = Depends(get_db), _: User = Depends(require_password_change_complete)):
    tanks = db.scalars(select(Tank).options(selectinload(Tank.customer)).order_by(Tank.name)).all()
    result = []
    now = datetime.now(timezone.utc)
    for tank in tanks:
        reading = db.scalar(select(SensorReading).where(SensorReading.tank_id == tank.id).order_by(SensorReading.timestamp.desc()).limit(1))
        stamp = reading.timestamp if reading else None
        if stamp and stamp.tzinfo is None: stamp = stamp.replace(tzinfo=timezone.utc)
        unresolved = list(db.scalars(select(Alert).where(Alert.tank_id == tank.id, Alert.is_resolved.is_(False))).all())
        result.append({"id": tank.id, "public_id": tank.public_id, "name": tank.name, "location": tank.location, "customer": {"id": tank.customer.id, "name": tank.customer.name} if tank.customer else None, "latest_reading": reading, "status": status_for_reading(db, reading), "last_reading_at": reading.timestamp if reading else None, "reporting_age_seconds": round((now-stamp).total_seconds()) if stamp else None, "active_warning_count": sum(a.severity.value == "warning" for a in unresolved), "active_critical_count": sum(a.severity.value == "critical" for a in unresolved)})
    return result

@router.get("/thresholds", response_model=list[ThresholdRead])
def thresholds(db: Session = Depends(get_db), _: User = Depends(require_password_change_complete)):
    return list(db.scalars(select(ThresholdConfig).order_by(ThresholdConfig.parameter)).all())

@router.put("/thresholds/{parameter}", response_model=ThresholdRead)
def update_threshold(parameter: str, payload: ThresholdUpdate, db: Session = Depends(get_db), _: User = Depends(require_admin)):
    item = db.scalar(select(ThresholdConfig).where(ThresholdConfig.parameter == parameter))
    if not item: raise HTTPException(404, "Threshold parameter not found")
    for key, value in payload.dict().items(): setattr(item, key, value)
    db.commit(); db.refresh(item); return item

@router.get("/analytics/fleet")
def analytics(range: str = Query("24h", regex="^(24h|7d|30d)$"), db: Session = Depends(get_db), _: User = Depends(require_password_change_complete)):
    hours, bucket_hours = {"24h": (24, .25), "7d": (168, 1), "30d": (720, 6)}[range]
    now = datetime.now(timezone.utc)
    start = now - timedelta(hours=hours)
    previous_start = start - timedelta(hours=hours)
    period_readings = list(db.scalars(
        select(SensorReading)
        .where(SensorReading.timestamp >= previous_start, SensorReading.timestamp < now)
        .order_by(SensorReading.timestamp)
    ).all())
    readings = [
        reading for reading in period_readings
        if (reading.timestamp.replace(tzinfo=timezone.utc) if reading.timestamp.tzinfo is None else reading.timestamp) >= start
    ]
    previous_readings = [
        reading for reading in period_readings
        if (reading.timestamp.replace(tzinfo=timezone.utc) if reading.timestamp.tzinfo is None else reading.timestamp) < start
    ]
    buckets = {}
    for r in readings:
        stamp = r.timestamp.replace(tzinfo=timezone.utc) if r.timestamp.tzinfo is None else r.timestamp
        epoch = int(stamp.timestamp() // (bucket_hours * 3600)) * bucket_hours * 3600
        bucket = buckets.setdefault(epoch, {"count": 0, "temperature": 0, "ph": 0, "turbidity": 0, "dissolved_oxygen": 0, "tds": 0, "ammonia": 0})
        bucket["count"] += 1
        for key in ("temperature", "ph", "turbidity", "dissolved_oxygen", "tds", "ammonia"): bucket[key] += getattr(r, key)
    series = [{"timestamp": datetime.fromtimestamp(k, timezone.utc).isoformat(), **{p: v[p]/v["count"] for p in ("temperature","ph","turbidity","dissolved_oxygen","tds","ammonia")}} for k,v in sorted(buckets.items())]
    alerts = list(db.scalars(select(Alert).where(Alert.created_at >= start)).all())
    counts = {"warning": sum(a.severity.value == "warning" for a in alerts), "critical": sum(a.severity.value == "critical" for a in alerts)}
    alert_buckets: dict[float, dict] = {}
    for alert in alerts:
        stamp = alert.created_at.replace(tzinfo=timezone.utc) if alert.created_at.tzinfo is None else alert.created_at
        epoch = int(stamp.timestamp() // (bucket_hours * 3600)) * bucket_hours * 3600
        bucket = alert_buckets.setdefault(epoch, {"warning": 0, "critical": 0})
        bucket[alert.severity.value] += 1
    alert_series = [
        {"timestamp": datetime.fromtimestamp(epoch, timezone.utc).isoformat(), **values}
        for epoch, values in sorted(alert_buckets.items())
    ]
    tanks = list(db.scalars(select(Tank)).all())
    expected_intervals = max(1, hours * 120)

    def unique_intervals(items: list[SensorReading], tank_id: int) -> int:
        return len({
            int(
                (
                    reading.timestamp.replace(tzinfo=timezone.utc)
                    if reading.timestamp.tzinfo is None
                    else reading.timestamp
                ).timestamp()
                // 30
            )
            for reading in items
            if reading.tank_id == tank_id
        })

    uptime = []
    for tank in tanks:
        current_intervals = unique_intervals(readings, tank.id)
        previous_intervals = unique_intervals(previous_readings, tank.id)
        uptime.append({
            "tank_id": tank.id,
            "tank_name": tank.name,
            "uptime": min(100, round(100 * current_intervals / expected_intervals, 1)),
            "previous_uptime": min(100, round(100 * previous_intervals / expected_intervals, 1)),
            "reported_intervals": current_intervals,
            "previous_reported_intervals": previous_intervals,
            "expected_intervals": expected_intervals,
        })

    current_fleet_uptime = round(sum(item["uptime"] for item in uptime) / len(uptime), 1) if uptime else 0.0
    previous_fleet_uptime = round(sum(item["previous_uptime"] for item in uptime) / len(uptime), 1) if uptime else 0.0
    return {
        "range": range,
        "series": series,
        "alert_counts": counts,
        "alert_series": alert_series,
        "uptime": uptime,
        "uptime_comparison": {
            "current": current_fleet_uptime,
            "previous": previous_fleet_uptime,
            "change": round(current_fleet_uptime - previous_fleet_uptime, 1),
        },
    }

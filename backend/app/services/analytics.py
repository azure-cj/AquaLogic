from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timedelta, timezone
from math import ceil
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import settings
from app.models import Alert, SensorReading, Tank, ThresholdConfig, ThresholdRevision
from app.services.decision_engine import PARAMETERS


def _aware(value: datetime) -> datetime:
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


def _empty_accumulator() -> dict[str, Any]:
    return {
        "count": 0,
        "contributors": set(),
        "sums": {parameter: 0.0 for parameter in PARAMETERS},
    }


def _empty_stat() -> dict[str, float | int | None]:
    return {"count": 0, "sum": 0.0, "minimum": None, "maximum": None}


def _add_stat(stat: dict[str, float | int | None], value: float) -> None:
    stat["count"] = int(stat["count"]) + 1
    stat["sum"] = float(stat["sum"]) + value
    stat["minimum"] = value if stat["minimum"] is None else min(float(stat["minimum"]), value)
    stat["maximum"] = value if stat["maximum"] is None else max(float(stat["maximum"]), value)


def _point_series(
    accumulators: dict[int, dict[str, Any]],
    start: datetime,
    bucket_seconds: int,
    bucket_count: int,
) -> list[dict[str, Any]]:
    result = []
    for index in range(bucket_count):
        accumulator = accumulators.get(index)
        count = int(accumulator["count"]) if accumulator else 0
        result.append(
            {
                "timestamp": start + timedelta(seconds=index * bucket_seconds),
                "values": {
                    parameter: round(float(accumulator["sums"][parameter]) / count, 4)
                    if accumulator and count
                    else None
                    for parameter in PARAMETERS
                },
                "sample_count": count,
                "contributor_count": len(accumulator["contributors"]) if accumulator else 0,
            }
        )
    return result


def _uptime_status(reported: int, uptime: float) -> str:
    if reported == 0:
        return "no_data"
    if uptime >= settings.analytics_uptime_warning:
        return "healthy"
    if uptime >= settings.analytics_uptime_critical:
        return "degraded"
    return "critical"


def _threshold_segments(
    db: Session,
    start: datetime,
    end: datetime,
) -> list[dict[str, Any]]:
    revisions = list(
        db.scalars(
            select(ThresholdRevision).order_by(
                ThresholdRevision.parameter,
                ThresholdRevision.effective_from,
                ThresholdRevision.id,
            )
        ).all()
    )
    configs = {
        item.parameter: item
        for item in db.scalars(select(ThresholdConfig).order_by(ThresholdConfig.parameter)).all()
    }
    by_parameter: dict[str, list[Any]] = defaultdict(list)
    for revision in revisions:
        by_parameter[revision.parameter].append(revision)

    segments: list[dict[str, Any]] = []
    for parameter in PARAMETERS:
        items = by_parameter.get(parameter, [])
        if not items and parameter in configs:
            items = [configs[parameter]]
        for index, item in enumerate(items):
            effective = (
                _aware(item.effective_from)
                if isinstance(item, ThresholdRevision)
                else start
            )
            following = (
                _aware(items[index + 1].effective_from)
                if index + 1 < len(items) and isinstance(items[index + 1], ThresholdRevision)
                else end
            )
            segment_start = max(start, effective)
            segment_end = min(end, following)
            if segment_start >= segment_end:
                continue
            segment = {
                "parameter": parameter,
                "unit": item.unit,
                "start": segment_start,
                "end": segment_end,
                "warning_min": item.warning_min,
                "warning_max": item.warning_max,
                "critical_min": item.critical_min,
                "critical_max": item.critical_max,
                "enabled": item.enabled,
            }
            comparable_fields = (
                "parameter",
                "unit",
                "warning_min",
                "warning_max",
                "critical_min",
                "critical_max",
                "enabled",
            )
            if (
                segments
                and segments[-1]["end"] == segment["start"]
                and all(
                    segments[-1][field] == segment[field]
                    for field in comparable_fields
                )
            ):
                segments[-1]["end"] = segment["end"]
            else:
                segments.append(segment)
    return segments


def build_fleet_analytics(
    db: Session,
    *,
    range_name: str,
    start: datetime,
    end: datetime,
    bucket_seconds: int,
    selected_tank_ids: list[int],
) -> dict[str, Any]:
    start, end = _aware(start), _aware(end)
    duration = end - start
    previous_start = start - duration
    bucket_count = ceil(duration.total_seconds() / bucket_seconds)
    tanks = list(db.scalars(select(Tank).order_by(Tank.name)).all())
    tank_names = {tank.id: tank.name for tank in tanks}
    selected = set(selected_tank_ids)

    fleet_current: dict[int, dict[str, Any]] = {}
    fleet_previous: dict[int, dict[str, Any]] = {}
    tank_current: dict[int, dict[int, dict[str, Any]]] = {
        tank_id: {} for tank_id in selected_tank_ids
    }
    diagnostic_tank_current: dict[int, dict[int, dict[str, Any]]] = {
        tank.id: {} for tank in tanks
    }
    current_stats = {parameter: _empty_stat() for parameter in PARAMETERS}
    previous_stats = {parameter: _empty_stat() for parameter in PARAMETERS}
    current_intervals: dict[int, set[int]] = defaultdict(set)
    previous_intervals: dict[int, set[int]] = defaultdict(set)
    tank_bucket_presence: dict[int, set[int]] = defaultdict(set)

    columns = [
        SensorReading.tank_id,
        SensorReading.timestamp,
        *[getattr(SensorReading, parameter) for parameter in PARAMETERS],
    ]
    rows = db.execute(
        select(*columns)
        .where(
            SensorReading.timestamp >= previous_start,
            SensorReading.timestamp < end,
        )
        .order_by(SensorReading.timestamp)
        .execution_options(yield_per=5_000)
    )
    for row in rows:
        tank_id = int(row[0])
        stamp = _aware(row[1])
        values = {parameter: float(row[index + 2]) for index, parameter in enumerate(PARAMETERS)}
        is_current = stamp >= start
        period_start = start if is_current else previous_start
        index = int((stamp - period_start).total_seconds() // bucket_seconds)
        if index < 0 or index >= bucket_count:
            continue
        target = fleet_current if is_current else fleet_previous
        accumulator = target.setdefault(index, _empty_accumulator())
        accumulator["count"] += 1
        accumulator["contributors"].add(tank_id)
        for parameter, value in values.items():
            accumulator["sums"][parameter] += value
            _add_stat(
                current_stats[parameter] if is_current else previous_stats[parameter],
                value,
            )

        interval = int(stamp.timestamp() // 30)
        if is_current:
            current_intervals[tank_id].add(interval)
            tank_bucket_presence[tank_id].add(index)
            diagnostic_accumulator = diagnostic_tank_current[tank_id].setdefault(
                index, _empty_accumulator()
            )
            diagnostic_accumulator["count"] += 1
            diagnostic_accumulator["contributors"].add(tank_id)
            for parameter, value in values.items():
                diagnostic_accumulator["sums"][parameter] += value
            if tank_id in selected:
                tank_accumulator = tank_current[tank_id].setdefault(index, _empty_accumulator())
                tank_accumulator["count"] += 1
                tank_accumulator["contributors"].add(tank_id)
                for parameter, value in values.items():
                    tank_accumulator["sums"][parameter] += value
        else:
            previous_intervals[tank_id].add(interval)

    stats: dict[str, dict[str, float | None]] = {}
    for parameter in PARAMETERS:
        current = current_stats[parameter]
        previous = previous_stats[parameter]
        current_average = (
            float(current["sum"]) / int(current["count"]) if current["count"] else None
        )
        previous_average = (
            float(previous["sum"]) / int(previous["count"]) if previous["count"] else None
        )
        absolute_change = (
            current_average - previous_average
            if current_average is not None and previous_average is not None
            else None
        )
        percent_change = (
            absolute_change / abs(previous_average) * 100
            if absolute_change is not None and previous_average not in (None, 0)
            else None
        )
        stats[parameter] = {
            "average": round(current_average, 4) if current_average is not None else None,
            "minimum": current["minimum"],
            "maximum": current["maximum"],
            "previous_average": round(previous_average, 4)
            if previous_average is not None
            else None,
            "absolute_change": round(absolute_change, 4)
            if absolute_change is not None
            else None,
            "percent_change": round(percent_change, 2)
            if percent_change is not None
            else None,
        }

    alert_buckets = [{"warning": 0, "critical": 0} for _ in range(bucket_count)]
    alert_events: list[dict[str, Any]] = []
    alert_columns = [
        Alert,
        Tank.name,
        *[getattr(SensorReading, parameter) for parameter in PARAMETERS],
    ]
    alert_rows = db.execute(
        select(*alert_columns)
        .join(Tank, Tank.id == Alert.tank_id)
        .outerjoin(SensorReading, SensorReading.id == Alert.reading_id)
        .where(Alert.created_at >= start, Alert.created_at < end)
        .order_by(Alert.created_at)
    ).all()
    for row in alert_rows:
        alert, tank_name = row[0], row[1]
        stamp = _aware(alert.created_at)
        index = int((stamp - start).total_seconds() // bucket_seconds)
        if 0 <= index < bucket_count:
            alert_buckets[index][alert.severity.value] += 1
        metric_index = PARAMETERS.index(alert.parameter) if alert.parameter in PARAMETERS else None
        value = row[metric_index + 2] if metric_index is not None else None
        alert_events.append(
            {
                "id": alert.id,
                "tank_id": alert.tank_id,
                "tank_name": tank_name,
                "reading_id": alert.reading_id,
                "parameter": alert.parameter,
                "severity": alert.severity.value,
                "message": alert.message,
                "timestamp": stamp,
                "value": float(value) if value is not None else None,
            }
        )

    expected_intervals = max(1, ceil(duration.total_seconds() / 30))
    uptime = []
    for tank in tanks:
        reported = len(current_intervals[tank.id])
        previous_reported = len(previous_intervals[tank.id])
        value = min(100.0, round(100 * reported / expected_intervals, 1))
        previous_value = min(100.0, round(100 * previous_reported / expected_intervals, 1))
        uptime.append(
            {
                "tank_id": tank.id,
                "tank_name": tank.name,
                "uptime": value,
                "previous_uptime": previous_value,
                "reported_intervals": reported,
                "previous_reported_intervals": previous_reported,
                "expected_intervals": expected_intervals,
                "status": _uptime_status(reported, value),
            }
        )
    status_order = {"critical": 0, "degraded": 1, "no_data": 2, "healthy": 3}
    uptime.sort(key=lambda item: (status_order[item["status"]], item["uptime"], item["tank_name"]))
    current_uptime = round(sum(item["uptime"] for item in uptime) / len(uptime), 1) if uptime else 0.0
    previous_uptime = (
        round(sum(item["previous_uptime"] for item in uptime) / len(uptime), 1)
        if uptime
        else 0.0
    )

    gap_count = 0
    for tank in tanks:
        in_gap = False
        presence = tank_bucket_presence[tank.id]
        for index in range(bucket_count):
            missing = index not in presence
            if missing and not in_gap:
                gap_count += 1
            in_gap = missing

    counts = {
        "warning": sum(bucket["warning"] for bucket in alert_buckets),
        "critical": sum(bucket["critical"] for bucket in alert_buckets),
    }
    lowest_reporting = next(
        (item for item in uptime if item["reported_intervals"] > 0),
        None,
    )
    primary_driver_by_metric: dict[str, int | None] = {}
    for parameter in PARAMETERS:
        deviations: list[tuple[float, int]] = []
        for tank in tanks:
            total, comparisons = 0.0, 0
            for index, tank_accumulator in diagnostic_tank_current[tank.id].items():
                fleet_accumulator = fleet_current.get(index)
                if not fleet_accumulator:
                    continue
                tank_value = (
                    tank_accumulator["sums"][parameter] / tank_accumulator["count"]
                )
                fleet_value = (
                    fleet_accumulator["sums"][parameter] / fleet_accumulator["count"]
                )
                total += abs(tank_value - fleet_value)
                comparisons += 1
            if comparisons:
                deviations.append((total / comparisons, tank.id))
        primary_driver_by_metric[parameter] = (
            max(deviations, default=(0.0, None))[1] if deviations else None
        )
    return {
        "window": {
            "range": range_name,
            "start": start,
            "end": end,
            "bucket_seconds": bucket_seconds,
            "timezone": "Asia/Manila",
        },
        "tanks": [{"id": tank.id, "name": tank.name} for tank in tanks],
        "fleet_series": _point_series(
            fleet_current, start, bucket_seconds, bucket_count
        ),
        "previous_fleet_series": _point_series(
            fleet_previous, previous_start, bucket_seconds, bucket_count
        ),
        "tank_series": [
            {
                "tank_id": tank_id,
                "tank_name": tank_names[tank_id],
                "series": _point_series(
                    tank_current[tank_id], start, bucket_seconds, bucket_count
                ),
            }
            for tank_id in selected_tank_ids
        ],
        "stats": stats,
        "alert_counts": counts,
        "alert_series": [
            {
                "timestamp": start + timedelta(seconds=index * bucket_seconds),
                **bucket,
            }
            for index, bucket in enumerate(alert_buckets)
        ],
        "alert_events": alert_events,
        "threshold_segments": _threshold_segments(db, start, end),
        "uptime": uptime,
        "uptime_comparison": {
            "current": current_uptime,
            "previous": previous_uptime,
            "change": round(current_uptime - previous_uptime, 1),
        },
        "uptime_thresholds": {
            "healthy": settings.analytics_uptime_warning,
            "degraded": settings.analytics_uptime_critical,
        },
        "insights": {
            "alert_count": counts["warning"] + counts["critical"],
            "reporting_gap_count": gap_count,
            "lowest_uptime_tank_id": lowest_reporting["tank_id"]
            if lowest_reporting
            else None,
            "primary_driver_by_metric": primary_driver_by_metric,
        },
    }

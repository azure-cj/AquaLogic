from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timedelta, timezone
from math import ceil
from typing import Any

from sqlalchemy import and_, or_, select
from sqlalchemy.orm import Session

from app.config import settings
from app.models import Alert, SensorReading, Tank
from app.services.decision_engine import PARAMETERS
from app.services.thresholds import effective_threshold_segments_by_tank
from app.services.analytics_insights import AnalyticsInsightAccumulator


WATER_QUALITY_BUCKET_SECONDS = 30 * 60


WATER_QUALITY_BUCKET_SECONDS = 30 * 60


def _aware(value: datetime) -> datetime:
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


def _floor_bucket(value: datetime, bucket_seconds: int) -> datetime:
    """Return the UTC clock boundary containing value."""
    epoch = int(_aware(value).timestamp())
    return datetime.fromtimestamp(epoch - epoch % bucket_seconds, tz=timezone.utc)


def _overlapping_bucket_count(start: datetime, end: datetime, bucket_seconds: int) -> int:
    aligned_start = _floor_bucket(start, bucket_seconds)
    return max(0, ceil((end - aligned_start).total_seconds() / bucket_seconds))


def _empty_accumulator() -> dict[str, Any]:
    return {
        "count": 0,
        "contributors": set(),
        "sums": {parameter: 0.0 for parameter in PARAMETERS},
        "parameter_counts": {parameter: 0 for parameter in PARAMETERS},
    }


def _empty_stat() -> dict[str, float | int | None]:
    return {"count": 0, "sum": 0.0, "minimum": None, "maximum": None}


def _add_stat(stat: dict[str, float | int | None], value: float) -> None:
    stat["count"] = int(stat["count"]) + 1
    stat["sum"] = float(stat["sum"]) + value
    stat["minimum"] = value if stat["minimum"] is None else min(float(stat["minimum"]), value)
    stat["maximum"] = value if stat["maximum"] is None else max(float(stat["maximum"]), value)


def _add_values(accumulator: dict[str, Any], values: dict[str, float | None]) -> None:
    """Accumulate only the metrics that were actually installed/reported."""
    for parameter, value in values.items():
        if value is None:
            continue
        accumulator["sums"][parameter] += value
        accumulator["parameter_counts"][parameter] += 1


def _point_series(
    accumulators: dict[int, dict[str, Any]],
    start: datetime,
    bucket_seconds: int,
    bucket_count: int,
) -> list[dict[str, Any]]:
    result = []
    for index in range(bucket_count):
        accumulator = accumulators.get(index)
        result.append(
            {
                "timestamp": start + timedelta(seconds=index * bucket_seconds),
                "values": {
                    parameter: round(
                        float(accumulator["sums"][parameter])
                        / int(accumulator["parameter_counts"][parameter]),
                        4,
                    )
                    if accumulator and accumulator["parameter_counts"][parameter]
                    else None
                    for parameter in PARAMETERS
                },
                "sample_count": int(accumulator["count"]) if accumulator else 0,
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


def _analytics_thresholds(
    db: Session,
    start: datetime,
    end: datetime,
    *,
    tanks: list[Tank],
    selected_tank_ids: list[int],
) -> dict[str, Any]:
    scope_ids = selected_tank_ids or [tank.id for tank in tanks]
    if len(selected_tank_ids) == 1:
        tank_id = selected_tank_ids[0]
        segments = effective_threshold_segments_by_tank(db, [tank_id], start, end)[tank_id]
        return {
            "threshold_segments": [{**item, "tank_id": tank_id} for item in segments],
            "threshold_scope": "tank",
            "threshold_tank_id": tank_id,
            "thresholds_vary_by_tank": False,
        }

    histories = effective_threshold_segments_by_tank(db, scope_ids, start, end)
    if not scope_ids:
        return {
            "threshold_segments": [],
            "threshold_scope": "shared",
            "threshold_tank_id": None,
            "thresholds_vary_by_tank": False,
        }

    comparable_fields = (
        "parameter",
        "unit",
        "start",
        "end",
        "warning_min",
        "warning_max",
        "critical_min",
        "critical_max",
        "enabled",
    )
    def signature(segments: list[dict]) -> list[tuple]:
        normalized: list[tuple] = []
        for segment in segments:
            state = tuple(
                segment[field]
                for field in comparable_fields
                if field not in {"start", "end"}
            )
            if normalized and normalized[-1][0] == state and normalized[-1][2] == segment["start"]:
                previous = normalized[-1]
                normalized[-1] = (state, previous[1], segment["end"])
            else:
                normalized.append((state, segment["start"], segment["end"]))
        return normalized

    signatures = [signature(histories[tank_id]) for tank_id in scope_ids]
    if any(signature != signatures[0] for signature in signatures[1:]):
        return {
            "threshold_segments": [],
            "threshold_scope": "varies",
            "threshold_tank_id": None,
            "thresholds_vary_by_tank": True,
        }

    shared_segments = [
        {**segment, "source": "shared", "tank_id": None}
        for segment in histories[scope_ids[0]]
    ]
    return {
        "threshold_segments": shared_segments,
        "threshold_scope": "shared",
        "threshold_tank_id": None,
        "thresholds_vary_by_tank": False,
    }


def build_fleet_analytics(
    db: Session,
    *,
    range_name: str,
    start: datetime,
    end: datetime,
    bucket_seconds: int,
    selected_tank_ids: list[int],
    include_retired: bool = False,
) -> dict[str, Any]:
    start, end = _aware(start), _aware(end)
    duration = end - start
    previous_start = start - duration
    bucket_count = ceil(duration.total_seconds() / bucket_seconds)
    water_quality_start = _floor_bucket(start, WATER_QUALITY_BUCKET_SECONDS)
    previous_water_quality_start = _floor_bucket(previous_start, WATER_QUALITY_BUCKET_SECONDS)
    water_quality_bucket_count = _overlapping_bucket_count(
        start, end, WATER_QUALITY_BUCKET_SECONDS
    )
    previous_water_quality_bucket_count = _overlapping_bucket_count(
        previous_start, start, WATER_QUALITY_BUCKET_SECONDS
    )
    tank_stmt = select(Tank).order_by(Tank.name)
    if not include_retired:
        tank_stmt = tank_stmt.where(Tank.retired_at.is_(None))
    tanks = list(db.scalars(tank_stmt).all())
    scope_tank_ids = {tank.id for tank in tanks}
    tank_names = {tank.id: tank.name for tank in tanks}
    selected = set(selected_tank_ids)
    interpretation_ids = selected_tank_ids or [tank.id for tank in tanks]
    interpretation = AnalyticsInsightAccumulator(start, end, tanks, selected_tank_ids,
        effective_threshold_segments_by_tank(db, interpretation_ids, start, end))

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
    reporting_bucket_presence: dict[int, set[int]] = defaultdict(set)

    columns = [
        SensorReading.tank_id,
        SensorReading.timestamp,
        SensorReading.received_at,
        *[getattr(SensorReading, parameter) for parameter in PARAMETERS],
        SensorReading.device_id,
        SensorReading.is_mock,
    ]
    rows = db.execute(
        select(*columns)
        .where(
            or_(
                and_(
                    SensorReading.timestamp >= previous_start,
                    SensorReading.timestamp < end,
                ),
                and_(
                    SensorReading.received_at >= previous_start,
                    SensorReading.received_at < end,
                ),
            ),
            SensorReading.tank_id.in_(scope_tank_ids),
        )
        .order_by(SensorReading.timestamp, SensorReading.received_at)
        .execution_options(yield_per=5_000)
    )
    for row in rows:
        tank_id = int(row[0])
        observation_at = _aware(row[1])
        received_at = _aware(row[2])
        values = {
            parameter: float(row[index + 3]) if row[index + 3] is not None else None
            for index, parameter in enumerate(PARAMETERS)
        }
        interpretation.add(tank_id, observation_at, received_at, values, (row[-2], row[-1]))

        # Reporting health describes when the backend accepted a report, even
        # when that report contains a historical observation timestamp.
        if previous_start <= received_at < end:
            receipt_interval = int(received_at.timestamp() // 30)
            if received_at >= start:
                current_intervals[tank_id].add(receipt_interval)
                reporting_index = int((received_at - start).total_seconds() // bucket_seconds)
                if 0 <= reporting_index < bucket_count:
                    reporting_bucket_presence[tank_id].add(reporting_index)
            else:
                previous_intervals[tank_id].add(receipt_interval)

        # Water-quality history follows when the sensor observation occurred.
        if not previous_start <= observation_at < end:
            continue
        is_current = observation_at >= start
        period_start = water_quality_start if is_current else previous_water_quality_start
        index = int(
            (_floor_bucket(observation_at, WATER_QUALITY_BUCKET_SECONDS) - period_start)
            .total_seconds()
            // WATER_QUALITY_BUCKET_SECONDS
        )
        period_bucket_count = (
            water_quality_bucket_count if is_current else previous_water_quality_bucket_count
        )
        if index < 0 or index >= period_bucket_count:
            continue
        target = fleet_current if is_current else fleet_previous
        accumulator = target.setdefault(index, _empty_accumulator())
        accumulator["count"] += 1
        accumulator["contributors"].add(tank_id)
        _add_values(accumulator, values)
        for parameter, value in values.items():
            if value is None:
                continue
            _add_stat(
                current_stats[parameter] if is_current else previous_stats[parameter],
                value,
            )

        if is_current:
            diagnostic_accumulator = diagnostic_tank_current[tank_id].setdefault(
                index, _empty_accumulator()
            )
            diagnostic_accumulator["count"] += 1
            diagnostic_accumulator["contributors"].add(tank_id)
            _add_values(diagnostic_accumulator, values)
            if tank_id in selected:
                tank_accumulator = tank_current[tank_id].setdefault(index, _empty_accumulator())
                tank_accumulator["count"] += 1
                tank_accumulator["contributors"].add(tank_id)
                _add_values(tank_accumulator, values)

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
        .where(
            Alert.created_at >= start,
            Alert.created_at < end,
            Tank.retired_at.is_(None) if not include_retired else True,
        )
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
        presence = reporting_bucket_presence[tank.id]
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
                tank_count = tank_accumulator["parameter_counts"][parameter]
                fleet_count = fleet_accumulator["parameter_counts"][parameter]
                if not tank_count or not fleet_count:
                    continue
                tank_value = (
                    tank_accumulator["sums"][parameter] / tank_count
                )
                fleet_value = (
                    fleet_accumulator["sums"][parameter] / fleet_count
                )
                total += abs(tank_value - fleet_value)
                comparisons += 1
            if comparisons:
                deviations.append((total / comparisons, tank.id))
        primary_driver_by_metric[parameter] = (
            max(deviations, default=(0.0, None))[1] if deviations else None
        )
    threshold_context = _analytics_thresholds(
        db,
        start,
        end,
        tanks=tanks,
        selected_tank_ids=selected_tank_ids,
    )
    return {
        "window": {
            "range": range_name,
            "start": start,
            "end": end,
            "bucket_seconds": bucket_seconds,
            "water_quality_bucket_seconds": WATER_QUALITY_BUCKET_SECONDS,
            "timezone": "Asia/Manila",
        },
        "tanks": [{"id": tank.id, "name": tank.name, "lifecycle": tank.lifecycle} for tank in tanks],
        "fleet_series": _point_series(
            fleet_current,
            water_quality_start,
            WATER_QUALITY_BUCKET_SECONDS,
            water_quality_bucket_count,
        ),
        "previous_fleet_series": _point_series(
            fleet_previous,
            previous_water_quality_start,
            WATER_QUALITY_BUCKET_SECONDS,
            previous_water_quality_bucket_count,
        ),
        "tank_series": [
            {
                "tank_id": tank_id,
                "tank_name": tank_names[tank_id],
                "series": _point_series(
                    tank_current[tank_id],
                    water_quality_start,
                    WATER_QUALITY_BUCKET_SECONDS,
                    water_quality_bucket_count,
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
        **threshold_context,
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
        "decision_support_insights": interpretation.finish(alert_events),
    }

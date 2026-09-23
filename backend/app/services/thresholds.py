"""Resolve global defaults and tank-specific threshold history."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Iterable

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import (
    TankThresholdOverride,
    TankThresholdRevision,
    ThresholdConfig,
    ThresholdRevision,
)


@dataclass(frozen=True)
class EffectiveThreshold:
    parameter: str
    unit: str
    warning_min: float | None
    warning_max: float | None
    critical_min: float | None
    critical_max: float | None
    enabled: bool
    source: str
    updated_at: datetime | None


def resolve_effective_thresholds(
    db: Session,
    tank_id: int | None,
    *,
    as_of: datetime | None = None,
) -> dict[str, EffectiveThreshold]:
    """Return whole current overrides or the configuration effective at a time."""

    global_rows = {
        item.parameter: item
        for item in db.scalars(select(ThresholdConfig).order_by(ThresholdConfig.parameter)).all()
    }
    if as_of is not None:
        effective_at = _aware(as_of)
        global_history: dict[str, list[ThresholdRevision]] = {}
        for revision in db.scalars(
            select(ThresholdRevision).order_by(
                ThresholdRevision.parameter,
                ThresholdRevision.effective_from,
                ThresholdRevision.id,
            )
        ).all():
            global_history.setdefault(revision.parameter, []).append(revision)
        tank_history: dict[str, list[TankThresholdRevision]] = {}
        if tank_id is not None:
            for revision in db.scalars(
                select(TankThresholdRevision)
                .where(TankThresholdRevision.tank_id == tank_id)
                .order_by(TankThresholdRevision.parameter, TankThresholdRevision.effective_from, TankThresholdRevision.id)
            ).all():
                tank_history.setdefault(revision.parameter, []).append(revision)

        result: dict[str, EffectiveThreshold] = {}
        for parameter, global_row in global_rows.items():
            global_revisions = global_history.get(parameter, [])
            global_revision = next(
                (
                    item
                    for item in reversed(global_revisions)
                    if _aware(item.effective_from) <= effective_at
                ),
                None,
            )
            # The first global revision is the historical baseline captured by
            # migration/initialization, even when a legacy observed timestamp
            # places it just after a reading's server receipt time.
            global_state = global_revision or (global_revisions[0] if global_revisions else global_row)
            tank_revisions = tank_history.get(parameter, [])
            tank_revision = next(
                (
                    item
                    for item in reversed(tank_revisions)
                    if _aware(item.effective_from) <= effective_at
                ),
                None,
            )
            if tank_revision is not None and tank_revision.is_override:
                result[parameter] = EffectiveThreshold(
                    parameter=parameter,
                    unit=tank_revision.unit or global_state.unit,
                    warning_min=tank_revision.warning_min,
                    warning_max=tank_revision.warning_max,
                    critical_min=tank_revision.critical_min,
                    critical_max=tank_revision.critical_max,
                    enabled=bool(tank_revision.enabled),
                    source="tank",
                    updated_at=_aware(tank_revision.effective_from),
                )
            else:
                result[parameter] = EffectiveThreshold(
                    parameter=parameter,
                    unit=global_state.unit,
                    warning_min=global_state.warning_min,
                    warning_max=global_state.warning_max,
                    critical_min=global_state.critical_min,
                    critical_max=global_state.critical_max,
                    enabled=global_state.enabled,
                    source="global",
                    updated_at=(
                        _aware(global_state.effective_from)
                        if isinstance(global_state, ThresholdRevision)
                        else global_state.updated_at
                    ),
                )
        return result

    override_rows = {
        item.parameter: item
        for item in (
            db.scalars(
                select(TankThresholdOverride).where(TankThresholdOverride.tank_id == tank_id)
            ).all()
            if tank_id is not None
            else []
        )
    }
    result: dict[str, EffectiveThreshold] = {}
    for parameter, global_row in global_rows.items():
        override = override_rows.get(parameter)
        item = override or global_row
        result[parameter] = EffectiveThreshold(
            parameter=parameter,
            unit=item.unit,
            warning_min=item.warning_min,
            warning_max=item.warning_max,
            critical_min=item.critical_min,
            critical_max=item.critical_max,
            enabled=item.enabled,
            source="tank" if override is not None else "global",
            updated_at=item.updated_at,
        )
    return result


def _aware(value: datetime) -> datetime:
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


def _snapshot(item: ThresholdRevision | ThresholdConfig) -> dict:
    return {
        "unit": item.unit,
        "warning_min": item.warning_min,
        "warning_max": item.warning_max,
        "critical_min": item.critical_min,
        "critical_max": item.critical_max,
        "enabled": item.enabled,
        "source": "global",
    }


def effective_threshold_segments_by_tank(
    db: Session,
    tank_ids: Iterable[int],
    start: datetime,
    end: datetime,
) -> dict[int, list[dict]]:
    """Build tank-effective history, falling back to global revisions after resets."""

    ids = list(dict.fromkeys(tank_ids))
    if not ids:
        return {}
    start, end = _aware(start), _aware(end)
    global_revisions = list(
        db.scalars(
            select(ThresholdRevision).order_by(
                ThresholdRevision.parameter,
                ThresholdRevision.effective_from,
                ThresholdRevision.id,
            )
        ).all()
    )
    global_configs = {
        item.parameter: item
        for item in db.scalars(select(ThresholdConfig).order_by(ThresholdConfig.parameter)).all()
    }
    tank_revisions = list(
        db.scalars(
            select(TankThresholdRevision)
            .where(TankThresholdRevision.tank_id.in_(ids))
            .order_by(
                TankThresholdRevision.tank_id,
                TankThresholdRevision.parameter,
                TankThresholdRevision.effective_from,
                TankThresholdRevision.id,
            )
        ).all()
    )

    global_by_parameter: dict[str, list[ThresholdRevision]] = {}
    for revision in global_revisions:
        global_by_parameter.setdefault(revision.parameter, []).append(revision)
    tank_by_parameter: dict[tuple[int, str], list[TankThresholdRevision]] = {}
    for revision in tank_revisions:
        tank_by_parameter.setdefault((revision.tank_id, revision.parameter), []).append(revision)

    result: dict[int, list[dict]] = {}
    parameters = sorted(global_configs)
    for tank_id in ids:
        segments: list[dict] = []
        for parameter in parameters:
            global_items = global_by_parameter.get(parameter, [])
            tank_items = tank_by_parameter.get((tank_id, parameter), [])
            global_events = [(_aware(item.effective_from), item) for item in global_items]
            tank_events = [(_aware(item.effective_from), item) for item in tank_items]
            event_times = sorted(
                {
                    stamp
                    for stamp, _ in (*global_events, *tank_events)
                    if start < stamp < end
                }
            )
            boundaries = [start, *event_times, end]
            for left, right in zip(boundaries, boundaries[1:]):
                if left >= right:
                    continue
                global_item = next(
                    (item for stamp, item in reversed(global_events) if stamp <= left), None
                )
                tank_item = next(
                    (item for stamp, item in reversed(tank_events) if stamp <= left), None
                )
                if tank_item is not None and tank_item.is_override:
                    snapshot = {
                        "unit": tank_item.unit,
                        "warning_min": tank_item.warning_min,
                        "warning_max": tank_item.warning_max,
                        "critical_min": tank_item.critical_min,
                        "critical_max": tank_item.critical_max,
                        "enabled": tank_item.enabled,
                        "source": "tank_override",
                    }
                elif global_item is not None:
                    snapshot = _snapshot(global_item)
                elif not global_events and parameter in global_configs:
                    snapshot = _snapshot(global_configs[parameter])
                else:
                    continue

                segment = {
                    "parameter": parameter,
                    "start": left,
                    "end": right,
                    **snapshot,
                }
                if (
                    segments
                    and segments[-1]["parameter"] == parameter
                    and segments[-1]["end"] == left
                    and all(
                        segments[-1][field] == segment[field]
                        for field in (
                            "unit",
                            "warning_min",
                            "warning_max",
                            "critical_min",
                            "critical_max",
                            "enabled",
                            "source",
                        )
                    )
                ):
                    segments[-1]["end"] = right
                else:
                    segments.append(segment)
        result[tank_id] = segments
    return result

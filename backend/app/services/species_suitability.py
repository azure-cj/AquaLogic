"""Derived species-care suitability for a tank's latest sensor reading."""
from datetime import datetime, timezone
from typing import Any

from app.services.reading_freshness import is_reading_current


PARAMETERS = (
    "temperature",
    "ph",
    "tds",
)

PARAMETER_METADATA = {
    "temperature": {"unit": "°C", "minimum": "ideal_temp_min", "maximum": "ideal_temp_max", "label": "Temperature"},
    "ph": {"unit": "pH", "minimum": "ideal_ph_min", "maximum": "ideal_ph_max", "label": "pH"},
    "tds": {"unit": "ppm", "minimum": "ideal_tds_min", "maximum": "ideal_tds_max", "label": "TDS"},
}


def _number(value: float | int) -> str:
    return f"{value:g}"


def _preferred_range(minimum: float | None, maximum: float | None, unit: str) -> str:
    if minimum is not None and maximum is not None:
        return f"{_number(minimum)}–{_number(maximum)} {unit}"
    if minimum is not None:
        return f"at least {_number(minimum)} {unit}"
    return f"at most {_number(maximum)} {unit}"


def _message(
    species_name: str,
    parameter: str,
    current_value: float | None,
    minimum: float | None,
    maximum: float | None,
    reason: str,
) -> str:
    meta = PARAMETER_METADATA[parameter]
    unit = meta["unit"]
    if reason == "within_preferred_range":
        return f"{species_name} is within its preferred {meta['label'].lower()} range."
    if reason == "below_preferred_minimum":
        return (
            f"{species_name} prefers {_preferred_range(minimum, maximum, unit)}, "
            f"but the tank is currently {_number(current_value)} {unit}."
        )
    if reason == "above_preferred_maximum":
        return (
            f"{species_name} prefers {_preferred_range(minimum, maximum, unit)}, "
            f"but the tank is currently {_number(current_value)} {unit}."
        )
    messages = {
        "species_range_missing": f"{species_name} has no preferred {meta['label'].lower()} range configured.",
        "no_current_reading": f"No current tank reading is available for {meta['label'].lower()}.",
        "stale_reading": f"The latest tank reading is too old to evaluate {meta['label'].lower()}.",
        "reading_value_missing": f"The current tank reading has no {meta['label'].lower()} value.",
        "invalid_species_range": f"{species_name} has an invalid preferred {meta['label'].lower()} range.",
    }
    return messages[reason]


def evaluate_check(
    species: Any,
    parameter: str,
    reading: Any | None,
    *,
    evaluated_at: datetime | None = None,
) -> dict[str, Any]:
    """Evaluate one preferred range without consulting operational thresholds."""
    meta = PARAMETER_METADATA[parameter]
    minimum = getattr(species, meta["minimum"]) if meta["minimum"] else None
    maximum = getattr(species, meta["maximum"]) if meta["maximum"] else None
    configured = minimum is not None or maximum is not None
    current_value = getattr(reading, parameter, None) if reading is not None else None
    base = {
        "parameter": parameter,
        "configured": configured,
        "current_value": current_value,
        "preferred_min": minimum,
        "preferred_max": maximum,
        "unit": meta["unit"],
    }

    if not configured:
        reason = "species_range_missing"
        return {**base, "status": "unavailable", "reason": reason, "message": _message(species.common_name, parameter, current_value, minimum, maximum, reason)}
    if minimum is not None and maximum is not None and minimum > maximum:
        reason = "invalid_species_range"
        return {**base, "status": "unavailable", "reason": reason, "message": _message(species.common_name, parameter, current_value, minimum, maximum, reason)}
    if reading is None:
        reason = "no_current_reading"
        return {**base, "status": "unavailable", "reason": reason, "message": _message(species.common_name, parameter, current_value, minimum, maximum, reason)}
    if not is_reading_current(reading.timestamp, received_at=getattr(reading, "received_at", None), evaluated_at=evaluated_at):
        reason = "stale_reading"
        return {**base, "status": "unavailable", "reason": reason, "message": _message(species.common_name, parameter, current_value, minimum, maximum, reason)}
    if current_value is None:
        reason = "reading_value_missing"
        return {**base, "status": "unavailable", "reason": reason, "message": _message(species.common_name, parameter, current_value, minimum, maximum, reason)}
    if minimum is not None and current_value < minimum:
        reason = "below_preferred_minimum"
        return {**base, "status": "attention", "reason": reason, "message": _message(species.common_name, parameter, current_value, minimum, maximum, reason)}
    if maximum is not None and current_value > maximum:
        reason = "above_preferred_maximum"
        return {**base, "status": "attention", "reason": reason, "message": _message(species.common_name, parameter, current_value, minimum, maximum, reason)}
    reason = "within_preferred_range"
    return {**base, "status": "suitable", "reason": reason, "message": _message(species.common_name, parameter, current_value, minimum, maximum, reason)}


def evaluate_species(species: Any, reading: Any | None, *, evaluated_at: datetime | None = None) -> dict[str, Any]:
    checks = [evaluate_check(species, parameter, reading, evaluated_at=evaluated_at) for parameter in PARAMETERS]
    configured_checks = [check for check in checks if check["configured"]]
    if any(check["status"] == "attention" for check in configured_checks):
        status = "attention"
    elif any(check["status"] == "unavailable" for check in configured_checks):
        status = "unavailable"
    elif configured_checks:
        status = "suitable"
    else:
        status = "unavailable"
    return {
        "fish_species_id": species.id,
        "common_name": species.common_name,
        "scientific_name": species.scientific_name,
        "status": status,
        "checks": checks,
    }


def evaluate_tank_species_suitability(
    tank: Any,
    reading: Any | None,
    *,
    evaluated_at: datetime | None = None,
) -> dict[str, Any]:
    now = evaluated_at or datetime.now(timezone.utc)
    if now.tzinfo is None:
        now = now.replace(tzinfo=timezone.utc)
    species = [evaluate_species(item, reading, evaluated_at=now) for item in tank.fish_species]
    counts = {status: sum(item["status"] == status for item in species) for status in ("suitable", "attention", "unavailable")}
    if not species:
        status, summary_reason = "unavailable", "no_species_assigned"
    elif counts["attention"]:
        status, summary_reason = "attention", None
    elif counts["unavailable"]:
        status, summary_reason = "unavailable", None
    else:
        status, summary_reason = "suitable", None
    freshness = "current" if reading is not None and is_reading_current(reading.timestamp, received_at=getattr(reading, "received_at", None), evaluated_at=now) else "stale"
    return {
        "tank_id": tank.id,
        "status": status,
        "summary_reason": summary_reason,
        "evaluated_at": now,
        "reading": None if reading is None else {"id": reading.id, "timestamp": reading.timestamp, "freshness": freshness},
        "species_counts": counts,
        "species": species,
    }

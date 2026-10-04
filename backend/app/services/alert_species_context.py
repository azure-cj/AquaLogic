"""Supplementary current species preferences; never operational thresholds."""
from math import isfinite

from app.services.species_suitability import PARAMETERS, PARAMETER_METADATA, evaluate_check
from app.services.reading_freshness import is_reading_current
from app.schemas.sensor import make_timestamp_explicit_utc

ADVISORY = "Stored species preferences provide additional context. AquaLogic alerts continue to use the tank's configured thresholds."
FUTURE_TOLERANCE_SECONDS = 5


def build_species_context(tank, parameter, reading, now):
    now = make_timestamp_explicit_utc(now)
    species = sorted({item.id: item for item in tank.fish_species}.values(), key=lambda item: (item.common_name, item.id))
    reason = None
    if parameter not in PARAMETERS:
        reason = "unsupported_parameter"
    elif reading is None:
        reason = "no_current_reading"
    else:
        observed = make_timestamp_explicit_utc(reading.timestamp)
        if (observed - now).total_seconds() > FUTURE_TOLERANCE_SECONDS:
            reason = "future_observation"
        elif not is_reading_current(reading.timestamp, received_at=reading.received_at, evaluated_at=now):
            reason = "stale_receipt"
        elif not is_reading_current(reading.timestamp, evaluated_at=now):
            reason = "stale_observation"
        elif getattr(reading, parameter, None) is None or not isfinite(getattr(reading, parameter)):
            reason = "reading_value_missing"
    rows = []
    for item in species:
        if parameter not in PARAMETERS:
            check = dict(preferred_min=None, preferred_max=None, status="unavailable", reason=reason)
        else:
            check = evaluate_check(item, parameter, reading, evaluated_at=now)
            bounds = (check["preferred_min"], check["preferred_max"])
            if any(value is not None and not isfinite(value) for value in bounds):
                check.update(status="unavailable", reason="invalid_species_range")
            elif check["status"] != "unavailable" and reason:
                check.update(status="unavailable", reason=reason)
        rows.append(dict(species_id=item.id, name=item.common_name,
                         stored_min=check["preferred_min"] if check["preferred_min"] is None or isfinite(check["preferred_min"]) else None,
                         stored_max=check["preferred_max"] if check["preferred_max"] is None or isfinite(check["preferred_max"]) else None,
                         result={"suitable": "within", "attention": "outside", "unavailable": "unavailable"}[check["status"]],
                         reason=check["reason"]))
    counts = {key: sum(row["result"] == key for row in rows) for key in ("within", "outside", "unavailable")}
    counts.update(assigned=len(rows), evaluable=counts["within"] + counts["outside"])
    if not species and reason is None:
        reason = "no_species_assigned"
    if counts["evaluable"] == 0 and reason is None:
        reason = "species_preferences_unavailable"
    return dict(parameter=parameter, basis="current_assignments_latest_reading",
                status="unsupported" if parameter not in PARAMETERS else "unavailable" if reason else "available",
                reason=reason, counts=counts, species=rows, advisory=ADVISORY,
                reading=None if reading is None else dict(reading_id=reading.id,
                    observed_at=make_timestamp_explicit_utc(reading.timestamp),
                    received_at=make_timestamp_explicit_utc(reading.received_at)),
                unit=PARAMETER_METADATA.get(parameter, {}).get("unit", "NTU" if parameter == "turbidity" else ""))

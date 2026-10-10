"""Bounded advisory push copy derived from existing operational context."""
from sqlalchemy import select

from app.models import SensorReading
from app.services.alert_species_context import build_species_context
from app.services.analytics_insights import aware
from app.services.current_insights import build_parameter_trend
from app.services.operator_guidance import guidance_for
from app.services.thresholds import resolve_effective_thresholds

ALERT_FALLBACK_TITLE = "Water-quality alert"
ALERT_FALLBACK_BODY = "{tank}: {parameter} {severity}. Open AquaLogic for details and suggested checks."
OUTAGE_FALLBACK_TITLE = "Monitoring outage"
OUTAGE_FALLBACK_BODY = "{tank} has stopped reporting. Open Monitoring in AquaLogic for outage history."
RECOVERY_FALLBACK_TITLE = "Monitoring restored"
RECOVERY_FALLBACK_BODY = "{tank} has resumed reporting. View Monitoring history in AquaLogic."
METADATA = {"temperature": ("Temperature", "°C"), "ph": ("pH", ""),
            "tds": ("TDS", "ppm"), "turbidity": ("Turbidity", "NTU")}


def _title(tank, suffix):
    name = tank.name
    available = 160 - len(suffix)
    if len(name) > available:
        name = name[:available - 1] + "…"
    return name + suffix


def _with_unit(text, unit):
    if not unit:
        return text
    return text + unit if unit == "°C" else f"{text} {unit}"


def _duration(minutes):
    minutes = round(minutes)
    if minutes < 60:
        return f"{minutes} minute" + ("" if minutes == 1 else "s")
    hours, rest = divmod(minutes, 60)
    text = f"{hours} h"
    return text + (f" {rest} min" if rest else "")


def _number(parameter, value):
    formatted = f"{value:.0f}" if parameter == "tds" else f"{value:.1f}"
    # Threshold configuration has no magnitude cap; keep extreme bounds compact.
    return formatted if len(formatted) <= 16 else f"{value:.1e}"


def compose_alert_push(db, alert, reading, tank, *, escalated: bool, now) -> tuple[str, str]:
    parameter = alert.parameter
    if parameter not in METADATA:
        return ALERT_FALLBACK_TITLE, ALERT_FALLBACK_BODY.format(
            tank=tank.name[:160], parameter=parameter.replace('_', ' ').title(),
            severity=alert.severity.value)[:300]
    label, unit = METADATA[parameter]
    value = getattr(reading, parameter)
    threshold = resolve_effective_thresholds(db, tank.id)[parameter]
    guidance = guidance_for(parameter, value, threshold)
    direction = guidance['direction']
    level = alert.severity.value
    bound = getattr(threshold, f"{level}_{'max' if direction == 'above' else 'min'}")
    if bound is None:
        raise ValueError("No breached bound for alert")
    severity = "now CRITICAL" if escalated else level
    title = _title(tank, f" · {label} {severity}: {_with_unit(_number(parameter, value), unit)}")
    required = f"{direction.capitalize()} the {_with_unit(_number(parameter, bound), unit)} {level} limit"
    trend = build_parameter_trend(db, tank.id, parameter, now=now)
    trend_text = ""
    if trend['status'] in {'rising', 'falling'}:
        rate = abs(trend['rate_per_hour'])
        # Small pH rates need another decimal to avoid claiming a zero rate.
        rate_text = f"{rate:.2f}" if 0 < rate < 0.1 else f"{rate:.1f}"
        trend_text = f" and {trend['status']} about {_with_unit(rate_text, unit)}/h"
    elif trend['status'] == 'steady':
        trend_text = "; little recent change"
    context = build_species_context(tank, parameter, reading, now)
    names = [item['name'] for item in context['species'] if item['result'] == 'outside']
    species_text = ""
    if names:
        names_text = ', '.join(names[:2]) + (f" +{len(names) - 2} more" if len(names) > 2 else "")
        species_text = f" Outside the comfort range for {names_text}."
    checks = [check.rstrip('.').lower() for check in guidance['checks'][:2]]

    checks = [check.replace('review ', 'check ', 1) if check.startswith('review ')
              else check.replace('verify ', 'confirm ', 1) if check.startswith('verify ')
              else check for check in checks]

    def body():
        return required + trend_text + "." + species_text + " First check: " + ", then ".join(checks) + "."

    if len(body()) > 300:
        species_text = ""
    if len(body()) > 300:
        trend_text = ""
    if len(body()) > 300:
        checks = checks[:1]
    return title, body()


def _range_text(db, tank, reading, *, present=False):
    one, many = ("is", "are") if present else ("was", "were")
    if reading is None:
        return f"readings {many} unavailable"
    thresholds = resolve_effective_thresholds(db, tank.id, as_of=reading.received_at)
    checked = 0
    missing = False
    outside = []
    for parameter in METADATA:
        threshold = thresholds.get(parameter)
        if threshold is None or not threshold.enabled:
            continue
        value = getattr(reading, parameter)
        if value is None:
            missing = True
            continue
        checked += 1
        lows = (threshold.warning_min, threshold.critical_min)
        highs = (threshold.warning_max, threshold.critical_max)
        if any(bound is not None and value < bound for bound in lows) or any(
                bound is not None and value > bound for bound in highs):
            outside.append(METADATA[parameter][0])
    if outside:
        return " and ".join(outside) + (f" {one}" if len(outside) == 1 else f" {many}") + " out of range"
    if not checked:
        return f"readings {many} unavailable"
    return f"available readings {many} in range" if missing else f"readings {many} in range"


def compose_outage_push(db, tank, incident, *, now) -> tuple[str, str]:
    latest = db.scalar(select(SensorReading).where(SensorReading.tank_id == tank.id,
        SensorReading.received_at <= (incident.last_reading_received_at or incident.started_at))
        .order_by(SensorReading.received_at.desc(), SensorReading.id.desc()).limit(1))
    baseline = incident.last_reading_received_at or incident.started_at
    minutes = max(0, (aware(now) - aware(baseline)).total_seconds() / 60)
    last = (f"Last reading at {aware(incident.last_reading_received_at).astimezone():%H:%M}, when "
            + _range_text(db, tank, latest) + "." if incident.last_reading_received_at
            else "No previous reading on record.")
    return _title(tank, " stopped reporting"), f"No data for {_duration(minutes)}. {last} First check: device power and Wi-Fi."


def compose_recovery_push(db, tank, incident, *, now) -> tuple[str, str]:
    latest = db.get(SensorReading, incident.recovery_reading_id) if incident.recovery_reading_id else None
    end = latest.received_at if latest else incident.resolved_at or now
    minutes = max(0, (aware(end) - aware(incident.started_at)).total_seconds() / 60)
    return _title(tank, " reporting again"), f"Back after {_duration(minutes)}. Now {_range_text(db, tank, latest, present=True)}."

"""Conservative operational checks; these are not diagnoses or corrective actions."""

ADVISORY = (
    "These checks are advisory. Confirm measurements and review the tank before acting. "
    "Handling or automatic resolution does not confirm water recovery."
)
CATALOGUE = {
    ("temperature", "above"): ["Confirm the measurement.", "Inspect the heater if installed.", "Review lighting duration.", "Verify circulation."],
    ("temperature", "below"): ["Confirm the measurement.", "Inspect the heater if installed.", "Review recent water changes and surrounding conditions."],
    ("ph", "above"): ["Confirm the measurement and probe calibration.", "Review dosing and recent water changes.", "Review available source-water information."],
    ("ph", "below"): ["Confirm the measurement and probe calibration.", "Review dosing and recent water changes.", "Review available source-water information."],
    ("turbidity", "above"): ["Confirm probe condition and the reading.", "Inspect visible cloudiness.", "Review feeding and maintenance.", "Inspect filtration and circulation."],
    ("tds", "above"): ["Confirm the measurement.", "Review available source-water information.", "Review top-ups, water changes, and additions."],
    ("tds", "below"): ["Confirm the measurement.", "Review available source-water information.", "Review top-ups, water changes, and additions."],
}


def guidance_for(parameter: str, value: float | None, threshold) -> dict:
    direction = "unavailable"
    if value is not None and threshold is not None and threshold.enabled:
        if any(bound is not None and value > bound for bound in (threshold.warning_max, threshold.critical_max)):
            direction = "above"
        elif any(bound is not None and value < bound for bound in (threshold.warning_min, threshold.critical_min)):
            direction = "below"
    checks = CATALOGUE.get((parameter, direction))
    if checks is None:
        direction = "unavailable"
        checks = ["Confirm the measurement.", "Review the configured thresholds.", "Inspect the tank and available reporting information."]
    label = "pH" if parameter == "ph" else parameter.replace("_", " ")
    return {
        "code": f"{parameter}.{direction}.v1",
        "direction": direction,
        "explanation": (f"The linked {label} reading is {direction} an associated configured bound. Review the checks below."
                        if direction != "unavailable" else "The linked reading or its direction is unavailable. Review the available context before acting."),
        "checks": checks,
        "advisory": ADVISORY,
    }

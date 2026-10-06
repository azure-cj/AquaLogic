"""Pure UTC curves shared by history and live demo ingestion.

The pH exhibit phase repeats every 28 days, with quiet history followed by
three elevated days. A bounded periodic curve cannot stay above its own
rolling baseline indefinitely; the exhibit phase is anchored explicitly.
"""
from datetime import datetime, timezone
from hashlib import sha256
from math import cos, pi, sin

SCENARIOS = {
    'DISPLAY-01': 'stable',
    'DISPLAY-02': 'warming',
    'BREED-01': 'stable',
    'BREED-02': 'unstable_ph',
    'SERVICE-01': 'offline',
    'RACK-01': 'species_conflict',
    'RACK-02': 'warming',
}
PARAMETERS = ('temperature', 'ph', 'turbidity', 'tds', 'dissolved_oxygen', 'ammonia')
VARIABILITY_EPOCH = datetime(2026, 10, 6, tzinfo=timezone.utc)
# Fixed hash seed supplies reproducible per-tank phases; smooth harmonics keep
# the resulting scatter continuous between 30-second samples.
_NOISE_PHASES = {code: tuple(2 * pi * int.from_bytes(sha256(('ci-v1:' + code).encode()).digest()[i:i + 4],
                              'big') / 2**32 for i in (0, 4)) for code in SCENARIOS}


def _seconds(t):
    if isinstance(t, datetime):
        return (t.replace(tzinfo=timezone.utc) if t.tzinfo is None else t).timestamp()
    return float(t)  # UTC epoch seconds, also useful for curve tests.


def _ph_amplitude(seconds):
    # Quiet for 23 days, one-day smooth increase, three-day plateau, one-day
    # smooth recovery. The plateau starts a day before the exhibit epoch so
    # the whole exhibit day has a complete elevated current window.
    day = ((seconds - VARIABILITY_EPOCH.timestamp()) / 86400 + 2) % 28
    if day < 1:
        envelope = (1 - cos(pi * day)) / 2
    elif day < 4:
        envelope = 1
    elif day < 5:
        envelope = (1 + cos(pi * (day - 4))) / 2
    else:
        envelope = 0
    return .018 * (1 + 1.5 * envelope)


def scenario_value(tank_code, parameter, t):
    """Return one unrounded measurement, independent of call order or RNG state."""
    role = SCENARIOS[tank_code]
    if parameter not in PARAMETERS:
        raise ValueError(f'Unsupported demo parameter: {parameter}')
    seconds = _seconds(t)
    hours = seconds / 3600
    # Deterministic, smooth small scatter. It cannot jump at sample boundaries.
    first_phase, second_phase = _NOISE_PHASES[tank_code]
    noise = sin(2 * pi * hours / 1.3 + first_phase) + .5 * sin(2 * pi * hours / .7 + second_phase)
    if parameter == 'temperature':
        if role == 'warming':
            phase = (hours + (4 if tank_code == 'RACK-02' else 0)) % 8
            # Default upper warning bound is 28 C. A 6.5-hour ascent from
            # mid-range to the bound, followed by a continuous 1.5-hour reset.
            return 24.8 + (3.2 * phase / 6.5 if phase < 6.5 else
                           3.2 * (8 - phase) / 1.5)
        if role == 'species_conflict':
            return 27.5 + .1 * sin(2 * pi * hours / 24) + .002 * noise
        return 25.0 + .3 * sin(2 * pi * hours / 24) + .002 * noise
    if parameter == 'ph':
        if role == 'unstable_ph':
            return 7.4 + _ph_amplitude(seconds) * sin(2 * pi * hours + first_phase)
        return (7.35 if tank_code in ('DISPLAY-02', 'BREED-01') else 6.9) + .003 * noise
    if parameter == 'tds':
        # Four-day evaporation cycle, continuous six-hour water-change reset.
        phase = hours % 96
        base = 190 if tank_code in ('DISPLAY-02', 'BREED-01', 'BREED-02') else 120
        return base + (24 * phase / 90 if phase < 90 else 4 * (96 - phase))
    if parameter == 'turbidity':
        return 2.8 + .15 * sin(2 * pi * hours / 6)
    if parameter == 'dissolved_oxygen':
        return 6.3 + .05 * sin(2 * pi * hours / 24)
    return .35 if tank_code == 'DISPLAY-02' else .7 if tank_code == 'BREED-01' else .09

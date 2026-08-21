"""Shared freshness rules for sensor readings."""
from datetime import datetime, timezone


READING_FRESHNESS_SECONDS = 90


def is_reading_current(
    timestamp: datetime,
    *,
    received_at: datetime | None = None,
    evaluated_at: datetime | None = None,
) -> bool:
    """Return whether a reading is within the current reporting window."""
    now = evaluated_at or datetime.now(timezone.utc)
    if now.tzinfo is None:
        now = now.replace(tzinfo=timezone.utc)
    reference = received_at or timestamp
    if reference.tzinfo is None:
        reference = reference.replace(tzinfo=timezone.utc)
    return (now - reference).total_seconds() <= READING_FRESHNESS_SECONDS

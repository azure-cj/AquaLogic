"""Shared freshness rules for sensor readings."""
from datetime import datetime, timezone


READING_FRESHNESS_SECONDS = 90


def is_reading_current(
    timestamp: datetime,
    *,
    evaluated_at: datetime | None = None,
) -> bool:
    """Return whether a reading is within the current reporting window."""
    now = evaluated_at or datetime.now(timezone.utc)
    if now.tzinfo is None:
        now = now.replace(tzinfo=timezone.utc)
    if timestamp.tzinfo is None:
        timestamp = timestamp.replace(tzinfo=timezone.utc)
    return (now - timestamp).total_seconds() <= READING_FRESHNESS_SECONDS

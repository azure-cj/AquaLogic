"""Shared permanent deletion step; callers own locking, audit and transaction."""
import logging
from pathlib import Path
from fastapi import HTTPException, status

logger = logging.getLogger(__name__)


def stage_retired_tank_deletion(db, tank):
    """Stage the existing relational cascade, returning media for post-commit cleanup."""
    if tank.retired_at is None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT,
                            detail="Tank must be retired before permanent deletion")
    hero_image_url = tank.hero_image_url
    db.delete(tank)
    return hero_image_url


def remove_local_hero_image(image_url: str | None, media_root_path, *, log=logger) -> None:
    if not image_url or not image_url.startswith("/api/media/tanks/"):
        return
    relative_name = image_url.removeprefix("/api/media/")
    target = (Path(media_root_path) / relative_name).resolve()
    media_root = Path(media_root_path).resolve()
    if media_root not in target.parents or not target.is_file():
        return
    try:
        target.unlink()
    except OSError:
        log.warning(
            "Tank-owned hero image cleanup failed after the database change: %s",
            relative_name,
            exc_info=True,
        )

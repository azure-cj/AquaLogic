from __future__ import annotations

import argparse
from contextlib import closing
import json
import os
import shutil
import sqlite3
import sys
import tarfile
import tempfile
from datetime import datetime, timezone
from pathlib import Path

from ._common import InvalidInputError, ToolError, is_within, relative_files, resolve_sqlite_path, sha256_file


FORMAT_VERSION = 1
DEFAULT_DATABASE_URL = "sqlite:///./aqualogic.db"
DEFAULT_MEDIA_ROOT = "./media"


def _parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create a paired AquaLogic SQLite and media backup bundle")
    parser.add_argument("--output-dir", required=True, help="Directory where the backup bundle will be written")
    parser.add_argument("--database-url", default=os.getenv("DATABASE_URL", DEFAULT_DATABASE_URL))
    parser.add_argument("--media-root", default=os.getenv("MEDIA_ROOT", DEFAULT_MEDIA_ROOT))
    return parser.parse_args(argv)


def _schema_revision(database_path: Path) -> str | None:
    with closing(sqlite3.connect(database_path)) as connection:
        row = connection.execute("SELECT version_num FROM alembic_version LIMIT 1").fetchone()
    return row[0] if row else None


def _integrity_check(database_path: Path) -> None:
    with closing(sqlite3.connect(database_path)) as connection:
        connection.execute("PRAGMA foreign_keys=ON")
        integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
        if integrity != "ok":
            raise ToolError(f"SQLite integrity_check failed: {integrity}")
        violations = connection.execute("PRAGMA foreign_key_check").fetchall()
        if violations:
            raise ToolError(f"SQLite foreign_key_check found {len(violations)} violation(s)")


def _copy_sqlite_backup(source: Path, target: Path) -> None:
    source_connection = sqlite3.connect(source)
    target_connection = sqlite3.connect(target)
    try:
        source_connection.backup(target_connection)
    except sqlite3.Error as error:
        raise ToolError(f"SQLite backup failed: {error}") from error
    finally:
        target_connection.close()
        source_connection.close()
    _integrity_check(target)


def _copy_media(source: Path, target: Path) -> list[dict[str, object]]:
    target.mkdir(parents=True, exist_ok=True)
    entries: list[dict[str, object]] = []
    for relative_path in relative_files(source):
        source_path = source / relative_path
        target_path = target / relative_path
        target_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_path, target_path)
        entries.append(
            {
                "path": str(Path("media") / relative_path).replace("\\", "/"),
                "size": target_path.stat().st_size,
                "sha256": sha256_file(target_path),
            }
        )
    return entries


def create_backup(*, output_dir: Path, database_url: str, media_root: Path) -> Path:
    database_path = resolve_sqlite_path(database_url)
    if not database_path.is_file():
        raise ToolError(f"SQLite database does not exist: {database_path}")
    media_root = media_root.expanduser().resolve()
    if media_root.exists() and not media_root.is_dir():
        raise InvalidInputError(f"MEDIA_ROOT must be a directory: {media_root}")
    output_dir = output_dir.expanduser().resolve()
    if is_within(output_dir, media_root):
        raise InvalidInputError("Backup output directory must not be inside MEDIA_ROOT")
    if output_dir == database_path:
        raise ToolError("Backup output directory must not be the database file")

    output_dir.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    archive_path = output_dir / f"aqualogic-backup-{timestamp}.tar.gz"
    if archive_path.exists():
        raise ToolError(f"Backup already exists for timestamp: {archive_path.name}")

    with tempfile.TemporaryDirectory(prefix=".aqualogic-backup-", dir=output_dir) as temporary_name:
        temporary_root = Path(temporary_name)
        temporary_database = temporary_root / "aqualogic.db"
        temporary_media = temporary_root / "media"
        _copy_sqlite_backup(database_path, temporary_database)
        media_entries = _copy_media(media_root, temporary_media)
        manifest = {
            "format_version": FORMAT_VERSION,
            "created_at": datetime.now(timezone.utc).isoformat(),
            "schema_revision": _schema_revision(temporary_database),
            "database": {
                "path": "aqualogic.db",
                "size": temporary_database.stat().st_size,
                "sha256": sha256_file(temporary_database),
            },
            "media": media_entries,
        }
        manifest_path = temporary_root / "manifest.json"
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        temporary_archive = output_dir / f".{archive_path.name}.tmp"
        try:
            with tarfile.open(temporary_archive, "w:gz") as archive:
                archive.add(manifest_path, arcname="manifest.json")
                archive.add(temporary_database, arcname="aqualogic.db")
                archive.add(temporary_media, arcname="media")
            temporary_archive.replace(archive_path)
        finally:
            temporary_archive.unlink(missing_ok=True)
    return archive_path


def main(argv: list[str] | None = None) -> int:
    try:
        args = _parse_args(argv)
        archive_path = create_backup(
            output_dir=Path(args.output_dir),
            database_url=args.database_url,
            media_root=Path(args.media_root),
        )
    except SystemExit:
        raise
    except InvalidInputError as error:
        print(f"Backup input rejected: {error}", file=sys.stderr)
        return 2
    except (OSError, sqlite3.Error, ToolError) as error:
        print(f"Backup failed: {error}", file=sys.stderr)
        return 1
    print(archive_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

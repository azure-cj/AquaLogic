from __future__ import annotations

import argparse
from contextlib import closing
import json
import shutil
import sqlite3
import subprocess
import sys
import tarfile
import tempfile
from datetime import datetime, timezone
from pathlib import Path

from ._common import InvalidInputError, ToolError, inherited_environment, sha256_file


FORMAT_VERSION = 1
PROJECT_ROOT = Path(__file__).resolve().parents[1]


def _parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Restore an AquaLogic backup into a new isolated directory")
    parser.add_argument("--bundle", required=True, help="Path to a paired .tar.gz backup bundle")
    parser.add_argument("--target-dir", required=True, help="New directory that will receive the restored application state")
    return parser.parse_args(argv)


def _safe_members(archive: tarfile.TarFile) -> list[tarfile.TarInfo]:
    members = archive.getmembers()
    names: set[str] = set()
    for member in members:
        path = Path(member.name)
        if member.name in names or path.is_absolute() or ".." in path.parts:
            raise InvalidInputError(f"Unsafe or duplicate archive path: {member.name}")
        if member.issym() or member.islnk():
            raise InvalidInputError(f"Archive links are not allowed: {member.name}")
        if member.name not in {"manifest.json", "aqualogic.db", "media"} and not member.name.startswith("media/"):
            raise InvalidInputError(f"Unexpected archive member: {member.name}")
        names.add(member.name)
    required = {"manifest.json", "aqualogic.db"}
    if not required.issubset(names):
        raise InvalidInputError("Backup bundle is missing manifest.json or aqualogic.db")
    return members


def _load_manifest(root: Path) -> dict:
    try:
        manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise InvalidInputError(f"Backup manifest is invalid: {error}") from error
    if not isinstance(manifest, dict):
        raise InvalidInputError("Backup manifest must be a JSON object")
    if manifest.get("format_version") != FORMAT_VERSION:
        raise InvalidInputError(f"Unsupported backup format: {manifest.get('format_version')}")
    database = manifest.get("database")
    if not isinstance(database, dict) or database.get("path") != "aqualogic.db":
        raise InvalidInputError("Backup manifest database path is invalid")
    media = manifest.get("media", [])
    if not isinstance(media, list):
        raise InvalidInputError("Backup manifest media must be a list")
    return manifest


def _verify_manifest(root: Path, manifest: dict) -> None:
    database = root / "aqualogic.db"
    expected_database = manifest["database"]
    try:
        database_size = expected_database["size"]
        database_sha256 = expected_database["sha256"]
    except (KeyError, TypeError) as error:
        raise InvalidInputError("Backup manifest database checksum metadata is invalid") from error
    if database.stat().st_size != database_size or sha256_file(database) != database_sha256:
        raise InvalidInputError("Restored database checksum does not match the manifest")
    expected_media: set[str] = set()
    for entry in manifest.get("media", []):
        if not isinstance(entry, dict):
            raise InvalidInputError("Backup manifest media entry is invalid")
        try:
            relative = Path(entry["path"])
            media_size = entry["size"]
            media_sha256 = entry["sha256"]
        except (KeyError, TypeError, ValueError) as error:
            raise InvalidInputError("Backup manifest media checksum metadata is invalid") from error
        normalized = relative.as_posix()
        if (
            relative.is_absolute()
            or ".." in relative.parts
            or len(relative.parts) < 2
            or relative.parts[0] != "media"
            or normalized in expected_media
        ):
            raise InvalidInputError(f"Invalid media path in manifest: {entry['path']}")
        path = root / relative
        if not path.is_file():
            raise InvalidInputError(f"Media file is missing from the bundle: {entry['path']}")
        if path.stat().st_size != media_size or sha256_file(path) != media_sha256:
            raise InvalidInputError(f"Media checksum does not match the manifest: {entry['path']}")
        expected_media.add(normalized)

    actual_media = {
        path.relative_to(root).as_posix()
        for path in (root / "media").rglob("*")
        if path.is_file()
    } if (root / "media").exists() else set()
    if actual_media != expected_media:
        raise InvalidInputError("Media files do not match the backup manifest")


def _run_migrations(database_path: Path, media_root: Path) -> None:
    environment = inherited_environment()
    environment["DATABASE_URL"] = f"sqlite:///{database_path.as_posix()}"
    environment["MEDIA_ROOT"] = str(media_root)
    result = subprocess.run(
        [sys.executable, "-m", "alembic", "-c", str(PROJECT_ROOT / "alembic.ini"), "upgrade", "head"],
        cwd=PROJECT_ROOT,
        env=environment,
        capture_output=True,
        text=True,
    )
    if result.returncode:
        detail = (result.stderr or result.stdout).strip()
        raise ToolError(f"Alembic upgrade failed: {detail}")


def _invalidate_sessions(database_path: Path) -> None:
    now = datetime.now(timezone.utc).isoformat()
    with closing(sqlite3.connect(database_path)) as connection:
        connection.execute("PRAGMA foreign_keys=ON")
        connection.execute(
            "UPDATE auth_sessions SET revoked_at = ?, revoke_reason = 'restore' WHERE revoked_at IS NULL",
            (now,),
        )
        connection.execute("UPDATE users SET token_version = token_version + 1")
        connection.commit()
        integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
        if integrity != "ok":
            raise ToolError(f"SQLite integrity_check failed after restore: {integrity}")
        violations = connection.execute("PRAGMA foreign_key_check").fetchall()
        if violations:
            raise ToolError(f"SQLite foreign_key_check found {len(violations)} violation(s) after restore")


def restore_bundle(*, bundle: Path, target_dir: Path) -> Path:
    bundle = bundle.expanduser().resolve()
    target_dir = target_dir.expanduser().resolve()
    if not bundle.is_file():
        raise ToolError(f"Backup bundle does not exist: {bundle}")
    if target_dir.exists():
        raise ToolError(f"Restore target must not already exist: {target_dir}")
    target_dir.parent.mkdir(parents=True, exist_ok=True)

    temporary_target = Path(tempfile.mkdtemp(prefix=f".{target_dir.name}.restore-", dir=target_dir.parent))
    try:
        with tarfile.open(bundle, "r:gz") as archive:
            members = _safe_members(archive)
            archive.extractall(temporary_target, members=members, filter="data")
        manifest = _load_manifest(temporary_target)
        _verify_manifest(temporary_target, manifest)
        database_path = temporary_target / "aqualogic.db"
        media_root = temporary_target / "media"
        _run_migrations(database_path, media_root)
        _invalidate_sessions(database_path)
        (temporary_target / "restore.json").write_text(
            json.dumps(
                {
                    "restored_at": datetime.now(timezone.utc).isoformat(),
                    "source_bundle": bundle.name,
                    "sessions_invalidated": True,
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
        if target_dir.exists():
            raise ToolError(f"Restore target appeared during restore: {target_dir}")
        temporary_target.replace(target_dir)
    except (OSError, sqlite3.Error, tarfile.TarError, subprocess.SubprocessError, ToolError):
        shutil.rmtree(temporary_target, ignore_errors=True)
        raise
    return target_dir


def main(argv: list[str] | None = None) -> int:
    try:
        args = _parse_args(argv)
        target_dir = restore_bundle(bundle=Path(args.bundle), target_dir=Path(args.target_dir))
    except SystemExit:
        raise
    except InvalidInputError as error:
        print(f"Restore input rejected: {error}", file=sys.stderr)
        return 2
    except (OSError, sqlite3.Error, tarfile.TarError, subprocess.SubprocessError, ToolError) as error:
        print(f"Restore failed: {error}", file=sys.stderr)
        return 1
    print(target_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

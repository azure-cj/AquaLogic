from __future__ import annotations

import hashlib
import os
from pathlib import Path
from urllib.parse import unquote


class ToolError(Exception):
    """Expected operator-facing error from a maintenance tool."""


class InvalidInputError(ToolError):
    """Operator input is unsupported or fails the bundle safety contract."""


def resolve_sqlite_path(database_url: str) -> Path:
    if not database_url.startswith("sqlite:///"):
        raise InvalidInputError("Only file-backed SQLite DATABASE_URL values are supported")
    raw_path = unquote(database_url.removeprefix("sqlite:///"))
    if not raw_path or raw_path in {":memory:", ":memory:"}:
        raise InvalidInputError("An in-memory SQLite database cannot be backed up")
    return Path(raw_path).expanduser().resolve()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def relative_files(root: Path) -> list[Path]:
    if not root.exists():
        return []
    if root.is_symlink():
        raise InvalidInputError(f"Media root must not be a symbolic link: {root}")
    files: list[Path] = []
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            raise InvalidInputError(f"Media tree must not contain symbolic links: {path}")
        if path.is_file():
            files.append(path.relative_to(root))
    return files


def is_within(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def inherited_environment() -> dict[str, str]:
    return dict(os.environ)

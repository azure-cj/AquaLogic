from __future__ import annotations

import json
import sqlite3
import tarfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

from app.database import Base, configure_sqlite_foreign_keys
from app.models import AuthSession, User
from app.security import get_password_hash
from scripts._common import ToolError
from scripts.backup_local import create_backup
from scripts.restore_local import restore_bundle


def _create_backup_source(tmp_path: Path) -> tuple[Path, Path]:
    database_path = tmp_path / "aqualogic.db"
    media_root = tmp_path / "media"
    media_root.mkdir()
    (media_root / "tanks").mkdir()
    (media_root / "tanks" / "tank.jpg").write_bytes(b"tank image")

    engine = create_engine(f"sqlite:///{database_path.as_posix()}", future=True)
    configure_sqlite_foreign_keys(engine)
    Base.metadata.create_all(bind=engine)
    with engine.begin() as connection:
        connection.execute(text("CREATE TABLE alembic_version (version_num VARCHAR(32) NOT NULL)"))
        connection.execute(text("INSERT INTO alembic_version (version_num) VALUES ('0008_actuator_controls')"))
    session_factory = sessionmaker(bind=engine, future=True)
    with session_factory() as db:
        user = User(
            name="Backup User",
            email="backup@example.com",
            hashed_password=get_password_hash("password123"),
            role="admin",
        )
        db.add(user)
        db.flush()
        db.add(
            AuthSession(
                id="backup-session",
                user_id=user.id,
                expires_at=datetime.now(timezone.utc) + timedelta(days=1),
                created_at=datetime.now(timezone.utc),
                last_seen_at=datetime.now(timezone.utc),
            )
        )
        db.commit()
    engine.dispose()
    return database_path, media_root


def test_backup_bundle_contains_database_media_manifest_and_checksums(tmp_path):
    database_path, media_root = _create_backup_source(tmp_path)
    output_dir = tmp_path / "backups"

    bundle = create_backup(
        output_dir=output_dir,
        database_url=f"sqlite:///{database_path.as_posix()}",
        media_root=media_root,
    )

    assert bundle.is_file()
    with tarfile.open(bundle, "r:gz") as archive:
        names = set(archive.getnames())
        manifest = json.load(archive.extractfile("manifest.json"))
    assert {"manifest.json", "aqualogic.db", "media", "media/tanks", "media/tanks/tank.jpg"} <= names
    assert manifest["format_version"] == 1
    assert manifest["schema_revision"] == "0008_actuator_controls"
    assert manifest["media"][0]["path"] == "media/tanks/tank.jpg"
    assert manifest["database"]["sha256"]


def test_restore_isolated_bundle_migrates_and_invalidates_sessions(tmp_path):
    database_path, media_root = _create_backup_source(tmp_path)
    bundle = create_backup(
        output_dir=tmp_path / "backups",
        database_url=f"sqlite:///{database_path.as_posix()}",
        media_root=media_root,
    )
    target = tmp_path / "restored"

    restored = restore_bundle(bundle=bundle, target_dir=target)

    assert restored == target
    assert (target / "media" / "tanks" / "tank.jpg").read_bytes() == b"tank image"
    with sqlite3.connect(target / "aqualogic.db") as connection:
        revoked_at, reason = connection.execute(
            "SELECT revoked_at, revoke_reason FROM auth_sessions WHERE id = 'backup-session'"
        ).fetchone()
        token_version = connection.execute(
            "SELECT token_version FROM users WHERE email = 'backup@example.com'"
        ).fetchone()[0]
    assert revoked_at is not None
    assert reason == "restore"
    assert token_version == 1
    assert (target / "restore.json").exists()


def test_restore_rejects_existing_target_without_modifying_it(tmp_path):
    database_path, media_root = _create_backup_source(tmp_path)
    bundle = create_backup(
        output_dir=tmp_path / "backups",
        database_url=f"sqlite:///{database_path.as_posix()}",
        media_root=media_root,
    )
    target = tmp_path / "existing"
    target.mkdir()
    marker = target / "marker.txt"
    marker.write_text("preserve", encoding="utf-8")

    with pytest.raises(ToolError, match="must not already exist"):
        restore_bundle(bundle=bundle, target_dir=target)
    assert marker.read_text(encoding="utf-8") == "preserve"


def test_restore_rejects_path_traversal_before_creating_target(tmp_path):
    bundle = tmp_path / "unsafe.tar.gz"
    with tarfile.open(bundle, "w:gz") as archive:
        manifest = tarfile.TarInfo("manifest.json")
        manifest_payload = b'{"format_version": 1, "database": {"path": "aqualogic.db"}}'
        manifest.size = len(manifest_payload)
        archive.addfile(manifest, __import__("io").BytesIO(manifest_payload))
        unsafe = tarfile.TarInfo("../outside.txt")
        unsafe_payload = b"unsafe"
        unsafe.size = len(unsafe_payload)
        archive.addfile(unsafe, __import__("io").BytesIO(unsafe_payload))

    with pytest.raises(ToolError, match="Unsafe"):
        restore_bundle(bundle=bundle, target_dir=tmp_path / "unsafe-target")
    assert not (tmp_path / "outside.txt").exists()


def test_restore_rejects_checksum_mismatch(tmp_path):
    database_path, media_root = _create_backup_source(tmp_path)
    original = create_backup(
        output_dir=tmp_path / "backups",
        database_url=f"sqlite:///{database_path.as_posix()}",
        media_root=media_root,
    )
    tampered = tmp_path / "tampered.tar.gz"
    with tarfile.open(original, "r:gz") as source, tarfile.open(tampered, "w:gz") as target:
        for member in source.getmembers():
            payload = source.extractfile(member).read() if member.isfile() else None
            if member.name == "media/tanks/tank.jpg":
                payload = b"tampered"
                member.size = len(payload)
            target.addfile(member, __import__("io").BytesIO(payload) if payload is not None else None)

    with pytest.raises(ToolError, match="checksum"):
        restore_bundle(bundle=tampered, target_dir=tmp_path / "tampered-target")
    assert not (tmp_path / "tampered-target").exists()

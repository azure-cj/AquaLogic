import logging
from pathlib import Path

import pytest

from app.config import settings
from app.models import Tank
from app.models import User
from app.security import get_password_hash


PNG_HEADER = b"\x89PNG\r\n\x1a\n" + b"demo-image"


def _tank(client, headers, name="Media Tank"):
    response = client.post("/tanks", headers=headers, json={"name": name, "location": "Gallery"})
    assert response.status_code == 201
    return response.json()


def _staff_headers(client, db_session):
    staff = User(
        name="Media Staff",
        email="media-staff@example.com",
        hashed_password=get_password_hash("password123"),
        role="staff",
    )
    db_session.add(staff)
    db_session.commit()
    login = client.post("/auth/login", json={"email": staff.email, "password": "password123"})
    return {"Authorization": f"Bearer {login.json()['access_token']}"}


def test_admin_can_upload_and_replace_a_tank_hero_image(client, auth_headers):
    tank = _tank(client, auth_headers)
    created = client.post(
        f"/tanks/{tank['id']}/hero-image",
        headers=auth_headers,
        files={"image": ("hero.png", PNG_HEADER, "image/png")},
    )
    assert created.status_code == 200
    payload = created.json()
    assert payload["hero_image_url"].startswith("/api/media/tanks/")
    assert payload["content_type"] == "image/png"
    assert payload["size_bytes"] == len(PNG_HEADER)

    detail = client.get(f"/tanks/{tank['id']}", headers=auth_headers)
    assert detail.json()["hero_image_url"] == payload["hero_image_url"]
    media = client.get(payload["hero_image_url"].replace("/api", "", 1))
    assert media.status_code == 200
    assert media.content == PNG_HEADER

    stored_file = Path(settings.media_root) / payload["hero_image_url"].removeprefix("/api/media/")
    stored_file.unlink(missing_ok=True)


def test_hero_image_upload_requires_admin_and_rejects_unsupported_content(client, auth_headers, db_session):
    tank = _tank(client, auth_headers, name="Protected Media Tank")
    staff_response = client.post(
        f"/tanks/{tank['id']}/hero-image",
        headers=_staff_headers(client, db_session),
        files={"image": ("hero.svg", b"<svg />", "image/svg+xml")},
    )
    assert staff_response.status_code == 403

    unsupported = client.post(
        f"/tanks/{tank['id']}/hero-image",
        headers=auth_headers,
        files={"image": ("hero.gif", b"GIF89a", "image/gif")},
    )
    assert unsupported.status_code == 415


def _upload_hero(client, headers, tank_id):
    response = client.post(
        f"/tanks/{tank_id}/hero-image",
        headers=headers,
        files={"image": ("hero.png", PNG_HEADER, "image/png")},
    )
    assert response.status_code == 200
    return response.json()["hero_image_url"]


def _stored_path(image_url: str) -> Path:
    return Path(settings.media_root) / image_url.removeprefix("/api/media/")


def _retire(client, headers, tank_id):
    response = client.post(f"/tanks/{tank_id}/retire", headers=headers, json={})
    assert response.status_code == 200


def test_deleting_tank_removes_owned_hero_image(client, auth_headers):
    tank = _tank(client, auth_headers, name="Delete Media Tank")
    image_url = _upload_hero(client, auth_headers, tank["id"])
    stored_file = _stored_path(image_url)
    assert stored_file.is_file()
    _retire(client, auth_headers, tank["id"])

    deleted = client.delete(f"/tanks/{tank['id']}", headers=auth_headers)

    assert deleted.status_code == 204
    assert not stored_file.exists()
    assert client.get(f"/tanks/{tank['id']}", headers=auth_headers).status_code == 404


def test_external_hero_url_is_not_treated_as_owned_file(client, auth_headers, monkeypatch):
    tank = _tank(client, auth_headers, name="External Media Tank")
    updated = client.put(
        f"/tanks/{tank['id']}",
        headers=auth_headers,
        json={"hero_image_url": "https://images.unsplash.com/tank.webp"},
    )
    assert updated.status_code == 200
    _retire(client, auth_headers, tank["id"])
    unlink_calls = []

    def unexpected_unlink(self, *args, **kwargs):
        unlink_calls.append(self)

    monkeypatch.setattr(Path, "unlink", unexpected_unlink)

    deleted = client.delete(f"/tanks/{tank['id']}", headers=auth_headers)

    assert deleted.status_code == 204
    assert unlink_calls == []


def test_missing_owned_hero_file_does_not_fail_tank_deletion(client, auth_headers):
    tank = _tank(client, auth_headers, name="Missing Media Tank")
    image_url = _upload_hero(client, auth_headers, tank["id"])
    stored_file = _stored_path(image_url)
    stored_file.unlink()
    _retire(client, auth_headers, tank["id"])

    deleted = client.delete(f"/tanks/{tank['id']}", headers=auth_headers)

    assert deleted.status_code == 204
    assert client.get(f"/tanks/{tank['id']}", headers=auth_headers).status_code == 404


def test_out_of_root_hero_path_cannot_delete_file_outside_media_root(client, auth_headers, db_session):
    tank = _tank(client, auth_headers, name="Traversal Media Tank")
    _retire(client, auth_headers, tank["id"])
    media_root = Path(settings.media_root).resolve()
    outside_file = media_root.parent / "aqualogic-goal2-outside.txt"
    outside_file.write_text("must remain", encoding="utf-8")
    tank_row = db_session.get(Tank, tank["id"])
    tank_row.hero_image_url = "/api/media/tanks/../../aqualogic-goal2-outside.txt"
    db_session.commit()

    try:
        deleted = client.delete(f"/tanks/{tank['id']}", headers=auth_headers)
        assert deleted.status_code == 204
        assert outside_file.read_text(encoding="utf-8") == "must remain"
    finally:
        outside_file.unlink(missing_ok=True)


def test_database_commit_failure_leaves_owned_hero_file_in_place(client, auth_headers, db_session, monkeypatch):
    tank = _tank(client, auth_headers, name="Commit Failure Media Tank")
    image_url = _upload_hero(client, auth_headers, tank["id"])
    stored_file = _stored_path(image_url)
    cleanup_calls = []
    _retire(client, auth_headers, tank["id"])

    from app.routes import tanks as tanks_route

    monkeypatch.setattr(tanks_route, "_remove_local_hero_image", lambda value: cleanup_calls.append(value))

    def fail_commit():
        raise RuntimeError("simulated database commit failure")

    monkeypatch.setattr(db_session, "commit", fail_commit)
    with pytest.raises(RuntimeError, match="simulated database commit failure"):
        client.delete(f"/tanks/{tank['id']}", headers=auth_headers)

    db_session.rollback()
    assert cleanup_calls == []
    assert stored_file.is_file()
    assert db_session.get(Tank, tank["id"]) is not None
    stored_file.unlink(missing_ok=True)


def test_post_commit_unlink_failure_does_not_resurrect_tank(client, auth_headers, caplog, monkeypatch):
    tank = _tank(client, auth_headers, name="Unlink Failure Media Tank")
    image_url = _upload_hero(client, auth_headers, tank["id"])
    stored_file = _stored_path(image_url)
    _retire(client, auth_headers, tank["id"])

    def fail_unlink(self, *args, **kwargs):
        raise OSError("simulated unlink failure")

    caplog.set_level(logging.WARNING, logger="app.routes.tanks")
    monkeypatch.setattr(Path, "unlink", fail_unlink)

    deleted = client.delete(f"/tanks/{tank['id']}", headers=auth_headers)

    assert deleted.status_code == 204
    assert client.get(f"/tanks/{tank['id']}", headers=auth_headers).status_code == 404
    assert stored_file.is_file()
    assert "Tank-owned hero image cleanup failed" in caplog.text
    monkeypatch.undo()
    stored_file.unlink(missing_ok=True)


def test_staff_cannot_delete_tank_or_owned_hero_file(client, auth_headers, db_session):
    tank = _tank(client, auth_headers, name="Staff Media Delete Tank")
    image_url = _upload_hero(client, auth_headers, tank["id"])
    stored_file = _stored_path(image_url)
    staff_headers = _staff_headers(client, db_session)

    denied = client.delete(f"/tanks/{tank['id']}", headers=staff_headers)

    assert denied.status_code == 403
    assert stored_file.is_file()
    stored_file.unlink(missing_ok=True)

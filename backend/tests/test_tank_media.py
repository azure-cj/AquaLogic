from pathlib import Path

from app.config import settings
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

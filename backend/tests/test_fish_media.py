from pathlib import Path

from app.config import settings
from app.models import User
from app.security import get_password_hash


PNG_HEADER = b"\x89PNG\r\n\x1a\nfish-photo"


def _fish(client, headers, common_name="Media Guppy"):
    response = client.post(
        "/fish",
        headers=headers,
        json={
            "common_name": common_name,
            "scientific_name": "Poecilia reticulata",
            "category": "Livebearers",
        },
    )
    assert response.status_code == 201
    return response.json()


def _staff_headers(client, db_session):
    staff = User(
        name="Fish Media Staff",
        email="fish-media-staff@example.com",
        hashed_password=get_password_hash("password123"),
        role="staff",
    )
    db_session.add(staff)
    db_session.commit()
    login = client.post("/auth/login", json={"email": staff.email, "password": "password123"})
    return {"Authorization": f"Bearer {login.json()['access_token']}"}


def test_admin_can_upload_and_replace_a_fish_photo(client, auth_headers):
    fish = _fish(client, auth_headers)
    created = client.post(
        f"/fish/{fish['id']}/photo-image",
        headers=auth_headers,
        files={"image": ("fish.png", PNG_HEADER, "image/png")},
    )
    assert created.status_code == 200
    payload = created.json()
    assert payload["photo_url"].startswith("/api/media/fish/")
    assert payload["content_type"] == "image/png"
    assert payload["size_bytes"] == len(PNG_HEADER)

    detail = client.get(f"/fish/{fish['id']}", headers=auth_headers)
    assert detail.json()["photo_url"] == payload["photo_url"]
    media = client.get(payload["photo_url"].replace("/api", "", 1))
    assert media.status_code == 200
    assert media.content == PNG_HEADER

    previous_file = Path(settings.media_root) / payload["photo_url"].removeprefix("/api/media/")
    replacement = client.post(
        f"/fish/{fish['id']}/photo-image",
        headers=auth_headers,
        files={"image": ("replacement.png", PNG_HEADER + b"-replacement", "image/png")},
    )
    assert replacement.status_code == 200
    assert not previous_file.exists()

    replacement_file = Path(settings.media_root) / replacement.json()["photo_url"].removeprefix("/api/media/")
    replacement_file.unlink(missing_ok=True)


def test_fish_photo_upload_is_admin_only_and_validates_image_type(client, auth_headers, db_session):
    fish = _fish(client, auth_headers, common_name="Protected Fish Photo")
    staff_response = client.post(
        f"/fish/{fish['id']}/photo-image",
        headers=_staff_headers(client, db_session),
        files={"image": ("fish.png", PNG_HEADER, "image/png")},
    )
    assert staff_response.status_code == 403

    unsupported = client.post(
        f"/fish/{fish['id']}/photo-image",
        headers=auth_headers,
        files={"image": ("fish.gif", b"GIF89a", "image/gif")},
    )
    assert unsupported.status_code == 415

    invalid = client.post(
        f"/fish/{fish['id']}/photo-image",
        headers=auth_headers,
        files={"image": ("fish.png", b"not-a-png", "image/png")},
    )
    assert invalid.status_code == 400

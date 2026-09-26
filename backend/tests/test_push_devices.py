import json
import logging
from datetime import timedelta

import pytest

from app.models import AuthSession, PushDevice, User
from app.security import get_password_hash, utc_now
from app.services.push_devices import eligible_push_devices
from sqlalchemy import select


def _body(
    installation_id="11111111-1111-4111-8111-111111111111",
    token="fcm-token-one",
    *,
    fid=None,
    fid_registered=False,
):
    body = {
        "installation_id": installation_id,
        "fcm_token": token,
        "platform": "android",
    }
    if fid is not None:
        body["firebase_installation_id"] = fid
    if fid_registered:
        body["firebase_installation_id_registered"] = True
    return body


def _register(client, headers, body=None):
    return client.put(
        "/push/devices/current",
        headers=headers,
        json=body or _body(),
    )


def _add_user(db_session, *, email, role="staff", active=True):
    user = User(
        name=email,
        email=email,
        hashed_password=get_password_hash("password123"),
        role=role,
        is_active=active,
    )
    db_session.add(user)
    db_session.commit()
    db_session.refresh(user)
    return user


def _login(client, user):
    response = client.post(
        "/auth/login",
        json={"email": user.email, "password": "password123"},
    )
    assert response.status_code == 200
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def test_push_device_registration_requires_authentication(client):
    assert _register(client, {}).status_code == 401


def test_staff_and_admin_can_register_without_exposing_the_token(client, test_user, db_session, caplog):
    caplog.set_level(logging.DEBUG)
    for role, installation_id, token in (
        ("staff", "11111111-1111-4111-8111-111111111111", "fcm-secret-staff"),
        ("admin", "22222222-2222-4222-8222-222222222222", "fcm-secret-admin"),
    ):
        test_user.role = role
        db_session.commit()
        response = _register(
            client,
            _login(client, test_user),
            _body(installation_id, token),
        )
        assert response.status_code == 200
        result = response.json()
        assert set(result) == {"id", "platform", "is_active", "last_registered_at"}
        assert result["platform"] == "android"
        assert token not in json.dumps(result)
        assert token not in caplog.text


def test_fid_is_stored_separately_and_never_returned_or_logged(
    client, auth_headers, db_session, caplog
):
    caplog.set_level(logging.DEBUG)
    fid = "firebase-installation-id-private"
    token = "separate-fcm-registration-token"
    response = _register(client, auth_headers, _body(token=token, fid=fid))

    assert response.status_code == 200
    result = response.json()
    device = db_session.scalar(select(PushDevice))
    assert device.firebase_installation_id == fid
    assert device.fcm_token == token
    assert device.firebase_installation_id_registered is False
    assert set(result) == {"id", "platform", "is_active", "last_registered_at"}
    assert fid not in json.dumps(result)
    assert token not in json.dumps(result)
    assert fid not in caplog.text
    assert token not in caplog.text


def test_registration_cannot_select_an_arbitrary_user_or_session(client, auth_headers):
    assert _register(
        client,
        auth_headers,
        {**_body(), "user_id": 999, "auth_session_id": "arbitrary"},
    ).status_code == 422


def test_repeated_registration_is_idempotent(client, auth_headers, db_session):
    first = _register(client, auth_headers)
    second = _register(client, auth_headers)

    assert first.status_code == second.status_code == 200
    assert first.json()["id"] == second.json()["id"]
    assert db_session.scalar(select(PushDevice.id)) is not None
    assert db_session.query(PushDevice).count() == 1


def test_token_refresh_updates_the_existing_installation(client, auth_headers, db_session):
    first = _register(client, auth_headers, _body(token="old-token"))
    refreshed = _register(client, auth_headers, _body(token="new-token"))

    assert first.json()["id"] == refreshed.json()["id"]
    device = db_session.scalar(select(PushDevice))
    assert device.fcm_token == "new-token"
    assert db_session.query(PushDevice).count() == 1


def test_fid_change_updates_the_same_device_without_renaming_the_fcm_token(
    client, auth_headers, db_session
):
    original = _register(
        client,
        auth_headers,
        _body(
            token="still-an-fcm-token",
            fid="old-firebase-installation-id",
            fid_registered=True,
        ),
    )
    changed = _register(
        client,
        auth_headers,
        _body(
            token="still-an-fcm-token",
            fid="new-firebase-installation-id",
            fid_registered=True,
        ),
    )

    device = db_session.scalar(select(PushDevice))
    assert original.json()["id"] == changed.json()["id"] == device.id
    assert device.firebase_installation_id == "new-firebase-installation-id"
    assert device.fcm_token == "still-an-fcm-token"
    assert device.firebase_installation_id_registered is True
    assert db_session.query(PushDevice).count() == 1


def test_fid_registration_is_idempotent(client, auth_headers, db_session):
    request = _body(
        token=None,
        fid="stable-firebase-installation-id",
        fid_registered=True,
    )
    first = _register(client, auth_headers, request)
    second = _register(client, auth_headers, request)

    assert first.status_code == second.status_code == 200
    assert first.json()["id"] == second.json()["id"]
    assert db_session.query(PushDevice).count() == 1
    device = db_session.scalar(select(PushDevice))
    assert device.fcm_token is None
    assert device.firebase_installation_id_registered is True


def test_old_client_refresh_falls_back_to_token_without_erasing_fid(
    client, auth_headers, db_session
):
    _register(
        client,
        auth_headers,
        _body(token=None, fid="registered-fid", fid_registered=True),
    )

    refreshed = _register(client, auth_headers, _body(token="legacy-refresh-token"))

    device = db_session.scalar(select(PushDevice))
    assert refreshed.status_code == 200
    assert device.fcm_token == "legacy-refresh-token"
    assert device.firebase_installation_id == "registered-fid"
    assert device.firebase_installation_id_registered is False


@pytest.mark.parametrize(
    "payload",
    [
        {"fcm_token": None},
        {
            "fcm_token": None,
            "firebase_installation_id": "unregistered-fid",
        },
        {
            "fcm_token": "legacy-token",
            "firebase_installation_id_registered": True,
        },
    ],
)
def test_registration_requires_a_deliverable_recipient(client, auth_headers, payload):
    response = _register(
        client,
        auth_headers,
        {**_body(), **payload},
    )
    assert response.status_code == 422


def test_installation_switches_safely_to_another_authenticated_account(
    client, auth_headers, test_user, db_session
):
    first = _register(client, auth_headers)
    first_device = db_session.scalar(select(PushDevice))
    first_session_id = first_device.auth_session_id
    second_user = _add_user(db_session, email="second@example.com", role="admin")
    second_headers = _login(client, second_user)

    second = _register(client, second_headers)

    assert second.json()["id"] == first.json()["id"]
    device = db_session.scalar(select(PushDevice))
    assert device.user_id == second_user.id
    assert device.auth_session_id != first_session_id
    assert db_session.get(AuthSession, device.auth_session_id).user_id == second_user.id
    assert device.user_id != test_user.id
    assert device.is_active is True

    # The previous account's still-valid session no longer owns this install.
    client.delete(
        f"/push/devices/current/{_body()['installation_id']}",
        headers=auth_headers,
    )
    assert device.is_active is True


def test_duplicate_fcm_token_moves_from_stale_installation_transactionally(
    client, auth_headers, db_session
):
    old_installation = "11111111-1111-4111-8111-111111111111"
    new_installation = "22222222-2222-4222-8222-222222222222"
    _register(client, auth_headers, _body(old_installation, "same-token"))

    response = _register(client, auth_headers, _body(new_installation, "same-token"))

    assert response.status_code == 200
    devices = db_session.scalars(select(PushDevice)).all()
    assert len(devices) == 1
    assert devices[0].installation_id == new_installation
    assert devices[0].fcm_token == "same-token"


def test_duplicate_fid_moves_from_stale_installation_transactionally(
    client, auth_headers, db_session
):
    fid = "same-firebase-installation-id"
    _register(client, auth_headers, _body(fid=fid))

    response = _register(
        client,
        auth_headers,
        _body(
            installation_id="22222222-2222-4222-8222-222222222222",
            token="new-fcm-token",
            fid=fid,
        ),
    )

    assert response.status_code == 200
    devices = db_session.scalars(select(PushDevice)).all()
    assert len(devices) == 1
    assert devices[0].firebase_installation_id == fid
    assert devices[0].fcm_token == "new-fcm-token"


def test_unsupported_platform_and_extra_identity_fields_are_rejected(client, auth_headers):
    assert _register(
        client,
        auth_headers,
        {**_body(), "platform": "ios"},
    ).status_code == 422


def test_invalid_registration_never_echoes_the_submitted_fcm_token(client, auth_headers):
    token = "private-fcm-token-that-must-not-be-reflected"
    response = _register(client, auth_headers, _body(token=f"{token} "))

    assert response.status_code == 422
    assert token not in response.text
    fid = "private-fid-value"
    invalid_fid = _register(
        client,
        auth_headers,
        _body(fid=f" {fid}"),
    )
    assert invalid_fid.status_code == 422
    assert fid not in invalid_fid.text
    assert _register(
        client,
        auth_headers,
        {**_body(), "auth_session_id": "client-selected"},
    ).status_code == 422


def test_deactivation_is_session_scoped_and_idempotent(client, auth_headers, test_user, db_session):
    _register(client, auth_headers)
    installation_id = _body()["installation_id"]

    response = client.delete(
        f"/push/devices/current/{installation_id}", headers=auth_headers
    )
    repeated = client.delete(
        f"/push/devices/current/{installation_id}", headers=auth_headers
    )

    device = db_session.scalar(select(PushDevice))
    assert response.status_code == repeated.status_code == 204
    assert device.user_id == test_user.id
    assert device.is_active is False
    assert device.disabled_at is not None


def test_registration_requires_completed_password_setup(client, test_user, db_session):
    test_user.must_change_password = True
    db_session.commit()
    # The login token remains valid, but staff routes enforce the password gate.
    response = client.post(
        "/auth/login",
        json={"email": test_user.email, "password": "password123"},
    )
    headers = {"Authorization": f"Bearer {response.json()['access_token']}"}
    assert _register(client, headers).status_code == 403


def test_revoked_expired_and_inactive_sessions_are_not_eligible(
    client, auth_headers, test_user, db_session
):
    _register(client, auth_headers)
    device = db_session.scalar(select(PushDevice))
    session = db_session.get(AuthSession, device.auth_session_id)

    assert eligible_push_devices(db_session)
    session.revoked_at = utc_now()
    db_session.commit()
    assert eligible_push_devices(db_session) == []

    session.revoked_at = None
    session.expires_at = utc_now() - timedelta(seconds=1)
    db_session.commit()
    assert eligible_push_devices(db_session) == []

    session.expires_at = utc_now() + timedelta(hours=1)
    test_user.is_active = False
    db_session.commit()
    assert eligible_push_devices(db_session) == []


def test_inactive_registration_is_not_eligible(client, auth_headers, db_session):
    _register(client, auth_headers)
    device = db_session.scalar(select(PushDevice))
    device.is_active = False
    db_session.commit()

    assert eligible_push_devices(db_session) == []

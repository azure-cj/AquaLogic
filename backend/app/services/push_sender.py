"""Safe server-side Firebase Cloud Messaging boundary.

Firebase imports, credential decoding, and app creation all happen on the first
send. Service-account material is read only from the process environment and is
never put in Settings, files, log messages, or exception text.
"""

import base64
import binascii
import json
import os
import threading
from collections.abc import Mapping
from typing import Protocol


class PushSendError(Exception):
    """A sanitized delivery failure suitable for persistence and logs."""

    error_code = "push_send_failed"

    def __init__(self) -> None:
        super().__init__(self.error_code)


class PushConfigurationError(PushSendError):
    error_code = "firebase_configuration_error"


class PushPermanentRecipientError(PushSendError):
    error_code = "unregistered_push_recipient"


class PushTransientError(PushSendError):
    error_code = "firebase_transient_error"


class PushSender(Protocol):
    def send(
        self,
        *,
        firebase_installation_id: str | None,
        fcm_token: str | None,
        title: str,
        body: str,
        data: Mapping[str, str],
    ) -> str: ...


class DisabledPushSender:
    """Explicit unavailable sender for a process with push disabled."""

    def send(
        self,
        *,
        firebase_installation_id: str | None,
        fcm_token: str | None,
        title: str,
        body: str,
        data: Mapping[str, str],
    ) -> str:
        raise PushConfigurationError()


class FirebaseAdminPushSender:
    """Send notification and versioned string data through Firebase Admin."""

    _APP_NAME = "aqualogic-push"

    def __init__(self) -> None:
        self._app = None
        self._lock = threading.Lock()

    def _get_app(self):
        if self._app is not None:
            return self._app

        with self._lock:
            if self._app is not None:
                return self._app

            encoded = os.environ.get("FIREBASE_SERVICE_ACCOUNT_JSON_B64", "").strip()
            if not encoded:
                raise PushConfigurationError()

            try:
                decoded = base64.b64decode(encoded, validate=True).decode("utf-8")
                service_account = json.loads(decoded)
                if not isinstance(service_account, dict):
                    raise ValueError
                if service_account.get("type") != "service_account":
                    raise ValueError
                service_project_id = service_account.get("project_id")
                configured_project_id = os.environ.get("FIREBASE_PROJECT_ID", "").strip()
                if not isinstance(service_project_id, str) or not service_project_id:
                    raise ValueError
                if configured_project_id and configured_project_id != service_project_id:
                    raise ValueError
            except (ValueError, UnicodeDecodeError, binascii.Error, json.JSONDecodeError):
                raise PushConfigurationError() from None

            try:
                import firebase_admin
                from firebase_admin import credentials

                try:
                    app = firebase_admin.get_app(self._APP_NAME)
                except ValueError:
                    options = {"projectId": configured_project_id or service_project_id}
                    certificate = credentials.Certificate(service_account)
                    app = firebase_admin.initialize_app(
                        certificate,
                        options=options,
                        name=self._APP_NAME,
                    )
            except Exception:
                # SDK exceptions may include certificate or project details.
                raise PushConfigurationError() from None

            self._app = app
            return app

    def validate_configuration(self) -> None:
        """Initialize credentials outside module import and without an FCM send."""
        self._get_app()

    def send(
        self,
        *,
        firebase_installation_id: str | None,
        fcm_token: str | None,
        title: str,
        body: str,
        data: Mapping[str, str],
    ) -> str:
        has_fid = isinstance(firebase_installation_id, str) and bool(firebase_installation_id)
        has_fcm_token = isinstance(fcm_token, str) and bool(fcm_token)
        if (
            (firebase_installation_id is not None and not has_fid)
            or (fcm_token is not None and not has_fcm_token)
            or (not has_fid and not has_fcm_token)
            or not isinstance(title, str)
            or not title
            or not isinstance(body, str)
            or not body
            or not isinstance(data, Mapping)
            or any(not isinstance(key, str) or not isinstance(value, str) for key, value in data.items())
        ):
            raise PushConfigurationError()

        app = self._get_app()
        try:
            from firebase_admin import messaging

            message = messaging.Message(
                **(
                    {"fid": firebase_installation_id}
                    if has_fid
                    else {"token": fcm_token}
                ),
                notification=messaging.Notification(title=title, body=body),
                data=dict(data),
            )
            return messaging.send(message, app=app)
        except Exception as exc:
            try:
                from firebase_admin import messaging

                unregistered_error = getattr(messaging, "UnregisteredError", None)
                if unregistered_error and isinstance(exc, unregistered_error):
                    raise PushPermanentRecipientError() from None
            except PushPermanentRecipientError:
                raise
            except Exception:
                pass

            if type(exc).__name__ in {
                "UnauthenticatedError",
                "PermissionDeniedError",
                "FailedPreconditionError",
            }:
                raise PushConfigurationError() from None
            raise PushTransientError() from None

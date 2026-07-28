import base64
import hashlib
import hmac
import secrets
from datetime import datetime, timedelta, timezone

import jwt
from pwdlib import PasswordHash

from .config import settings


password_hash = PasswordHash.recommended()


def _passlib_base64(value: str) -> bytes:
    return base64.b64decode(value.replace(".", "+") + "=" * (-len(value) % 4))


def _verify_legacy_pbkdf2(password: str, stored_hash: str) -> bool:
    """Verify the PBKDF2-SHA256 format emitted by the previous Passlib setup."""
    try:
        _, scheme, rounds, salt, checksum = stored_hash.split("$", 4)
        if scheme != "pbkdf2-sha256":
            return False
        actual = hashlib.pbkdf2_hmac(
            "sha256", password.encode(), _passlib_base64(salt), int(rounds)
        )
        return hmac.compare_digest(actual, _passlib_base64(checksum))
    except (TypeError, ValueError):
        return False


def verify_password(plain_password: str, hashed_password: str) -> bool:
    if hashed_password.startswith("$argon2"):
        try:
            return password_hash.verify(plain_password, hashed_password)
        except Exception:
            return False
    return _verify_legacy_pbkdf2(plain_password, hashed_password)


def password_needs_rehash(hashed_password: str) -> bool:
    return not hashed_password.startswith("$argon2")


def get_password_hash(password: str) -> str:
    return password_hash.hash(password)


def hash_opaque_token(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


def opaque_token() -> str:
    return secrets.token_urlsafe(48)


def anonymized_value(value: str) -> str:
    return hmac.new(settings.jwt_secret_key.encode(), value.encode(), hashlib.sha256).hexdigest()


def normalize_email(value: str) -> str:
    return value.strip().lower()


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def create_access_token(*, user_id: int, session_id: str, token_version: int, amr: str = "pwd") -> tuple[str, datetime]:
    issued_at = utc_now()
    expires_at = issued_at + timedelta(minutes=settings.access_token_expire_minutes)
    payload = {
        "sub": str(user_id),
        "sid": session_id,
        "ver": token_version,
        "iss": settings.jwt_issuer,
        "aud": settings.jwt_audience,
        "iat": issued_at,
        "exp": expires_at,
        "jti": secrets.token_urlsafe(18),
        "amr": [amr],
    }
    return jwt.encode(payload, settings.jwt_secret_key, algorithm="HS256"), expires_at


def decode_access_token(token: str) -> dict:
    return jwt.decode(
        token,
        settings.jwt_secret_key,
        algorithms=["HS256"],
        audience=settings.jwt_audience,
        issuer=settings.jwt_issuer,
        options={"require": ["sub", "sid", "ver", "iss", "aud", "iat", "exp", "jti", "amr"]},
    )

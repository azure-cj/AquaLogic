"""Create the first AquaLogic administrator from explicit environment values."""

import argparse
import os
import sys
from dataclasses import dataclass
from typing import Callable, Mapping, Sequence

from pydantic import ValidationError
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.database import SessionLocal
from app.models import User
from app.schemas.user import UserCreate
from app.security import get_password_hash, normalize_email, utc_now


class BootstrapError(Exception):
    """A safe-to-display bootstrap error that contains no credential values."""


@dataclass(frozen=True)
class BootstrapCredentials:
    name: str
    email: str
    password: str


def _credentials_from_environment(environment: Mapping[str, str]) -> BootstrapCredentials:
    required = (
        "ADMIN_BOOTSTRAP_EMAIL",
        "ADMIN_BOOTSTRAP_PASSWORD",
        "ADMIN_BOOTSTRAP_NAME",
    )
    missing = [key for key in required if not environment.get(key, "").strip()]
    if missing:
        raise BootstrapError("Missing required environment variable(s): " + ", ".join(missing))

    raw_email = environment["ADMIN_BOOTSTRAP_EMAIL"].strip()
    name = environment["ADMIN_BOOTSTRAP_NAME"].strip()
    password = environment["ADMIN_BOOTSTRAP_PASSWORD"]
    if len(password) < 12 or len(password) > 128 or not password.strip():
        raise BootstrapError("ADMIN_BOOTSTRAP_PASSWORD must be 12 to 128 characters and not blank")

    try:
        user_input = UserCreate(name=name, email=raw_email, role="admin")
    except ValidationError as exc:
        invalid_fields = {str(error["loc"][0]) for error in exc.errors() if error.get("loc")}
        if "email" in invalid_fields:
            raise BootstrapError("ADMIN_BOOTSTRAP_EMAIL must be a valid email address") from None
        if "name" in invalid_fields:
            raise BootstrapError("ADMIN_BOOTSTRAP_NAME must be 1 to 120 characters") from None
        raise BootstrapError("Bootstrap account details are invalid") from None

    return BootstrapCredentials(
        name=user_input.name,
        email=normalize_email(str(user_input.email)),
        password=password,
    )


def _create_first_admin(db: Session, credentials: BootstrapCredentials) -> str:
    try:
        with db.begin():
            existing_user_id = db.scalar(
                select(User.id).where(func.lower(User.email) == credentials.email).limit(1)
            )
            if existing_user_id is not None:
                return "existing_user"

            existing_admin_id = db.scalar(
                select(User.id).where(User.role == "admin").limit(1)
            )
            if existing_admin_id is not None:
                return "existing_admin"

            db.add(
                User(
                    name=credentials.name,
                    email=credentials.email,
                    role="admin",
                    hashed_password=get_password_hash(credentials.password),
                    is_active=True,
                    must_change_password=False,
                    password_changed_at=utc_now(),
                )
            )
        return "created"
    except Exception:
        db.rollback()
        raise BootstrapError("Administrator creation failed; the transaction was rolled back") from None


def main(
    argv: Sequence[str] | None = None,
    *,
    environ: Mapping[str, str] | None = None,
    session_factory: Callable[[], Session] | None = None,
    stdout: Callable[[str], None] = print,
    stderr: Callable[[str], None] = print,
) -> int:
    parser = argparse.ArgumentParser(
        description="Create the first AquaLogic administrator from ADMIN_BOOTSTRAP_* environment variables."
    )
    parser.parse_args(argv)

    try:
        credentials = _credentials_from_environment(os.environ if environ is None else environ)
    except BootstrapError as exc:
        stderr(str(exc))
        return 2

    factory = SessionLocal if session_factory is None else session_factory
    try:
        with factory() as db:
            result = _create_first_admin(db, credentials)
    except BootstrapError as exc:
        stderr(str(exc))
        return 1
    except Exception:
        stderr("Could not connect to the database or create the administrator; no credentials were logged")
        return 1

    if result == "created":
        stdout("Administrator account created successfully")
    elif result == "existing_user":
        stdout("Account already exists; no changes made")
    else:
        stdout("An administrator account already exists; no new account was created")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

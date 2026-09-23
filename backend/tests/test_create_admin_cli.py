from sqlalchemy import event, func, select
from sqlalchemy.orm import sessionmaker

from app.cli.create_admin import main
from app.database import Base
from app.models import User
from app.security import get_password_hash, verify_password


PASSWORD = "safe-bootstrap-password-1"


def _environment(**overrides):
    values = {
        "ADMIN_BOOTSTRAP_EMAIL": "owner@example.com",
        "ADMIN_BOOTSTRAP_PASSWORD": PASSWORD,
        "ADMIN_BOOTSTRAP_NAME": "AquaLogic Owner",
    }
    values.update(overrides)
    return values


def _factory_for(db_session):
    return sessionmaker(
        bind=db_session.get_bind(),
        autoflush=False,
        autocommit=False,
        future=True,
    )


def _run(db_session, environment, stdout=None, stderr=None):
    return main(
        [],
        environ=environment,
        session_factory=_factory_for(db_session),
        stdout=stdout if stdout is not None else lambda _: None,
        stderr=stderr if stderr is not None else lambda _: None,
    )


def test_bootstrap_creates_admin_with_existing_password_hash_and_no_demo_data(db_session):
    output = []

    result = _run(db_session, _environment(), stdout=output.append)

    assert result == 0
    assert output == ["Administrator account created successfully"]
    user = db_session.scalar(select(User))
    assert user is not None
    assert user.email == "owner@example.com"
    assert user.role == "admin"
    assert user.is_active is True
    assert user.must_change_password is False
    assert user.hashed_password != PASSWORD
    assert user.hashed_password.startswith("$argon2")
    assert verify_password(PASSWORD, user.hashed_password)

    for table in Base.metadata.sorted_tables:
        if table.name != User.__tablename__:
            assert db_session.scalar(select(func.count()).select_from(table)) == 0


def test_missing_required_environment_fails_before_opening_database(db_session):
    errors = []
    database_opened = False

    def forbidden_session_factory():
        nonlocal database_opened
        database_opened = True
        raise AssertionError("database should not be opened for missing credentials")

    result = main(
        [],
        environ={"ADMIN_BOOTSTRAP_EMAIL": "owner@example.com"},
        session_factory=forbidden_session_factory,
        stderr=errors.append,
    )

    assert result == 2
    assert "ADMIN_BOOTSTRAP_PASSWORD" in errors[0]
    assert "ADMIN_BOOTSTRAP_NAME" in errors[0]
    assert database_opened is False
    assert db_session.scalar(select(func.count()).select_from(User)) == 0


def test_existing_email_is_a_clean_no_op_and_does_not_change_password(db_session):
    existing = User(
        name="Existing Account",
        email="owner@example.com",
        role="staff",
        hashed_password=get_password_hash("different-password-123"),
    )
    db_session.add(existing)
    db_session.commit()
    original_hash = existing.hashed_password
    output = []

    result = _run(db_session, _environment(), stdout=output.append)

    db_session.expire_all()
    assert result == 0
    assert output == ["Account already exists; no changes made"]
    assert db_session.scalar(select(func.count()).select_from(User)) == 1
    assert db_session.scalar(select(User)).hashed_password == original_hash


def test_rerunning_bootstrap_is_safe_and_does_not_print_password(db_session):
    output = []

    first_result = _run(db_session, _environment(), stdout=output.append)
    second_result = _run(db_session, _environment(), stdout=output.append)

    assert first_result == second_result == 0
    assert db_session.scalar(select(func.count()).select_from(User)) == 1
    assert PASSWORD not in " ".join(output)
    assert output[1] == "Account already exists; no changes made"


def test_existing_different_admin_prevents_bootstrapping_a_second_admin(db_session):
    db_session.add(
        User(
            name="Existing Admin",
            email="existing-admin@example.com",
            role="admin",
            hashed_password=get_password_hash("existing-admin-password-1"),
        )
    )
    db_session.commit()
    output = []

    result = _run(db_session, _environment(), stdout=output.append)

    assert result == 0
    assert output == ["An administrator account already exists; no new account was created"]
    assert db_session.scalar(select(func.count()).select_from(User)) == 1


def test_creation_failure_rolls_back_and_does_not_print_password(db_session):
    engine = db_session.get_bind()

    def fail_user_insert(_connection, _cursor, statement, _parameters, _context, _executemany):
        if statement.lstrip().upper().startswith("INSERT INTO USERS"):
            raise RuntimeError("injected insert failure")

    event.listen(engine, "before_cursor_execute", fail_user_insert)
    factory = _factory_for(db_session)
    errors = []

    try:
        result = main(
            [],
            environ=_environment(),
            session_factory=factory,
            stderr=errors.append,
        )
    finally:
        event.remove(engine, "before_cursor_execute", fail_user_insert)

    db_session.expire_all()
    assert result == 1
    assert errors == ["Administrator creation failed; the transaction was rolled back"]
    assert PASSWORD not in errors[0]
    assert db_session.scalar(select(func.count()).select_from(User)) == 0

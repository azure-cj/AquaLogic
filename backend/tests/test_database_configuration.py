import pytest
from alembic.config import Config

from app import config as app_config


@pytest.fixture
def clean_database_environment(monkeypatch):
    for name in (
        "ENVIRONMENT",
        "DATABASE_URL",
        "JWT_SECRET_KEY",
        "CORS_ORIGINS",
        "TRUSTED_HOSTS",
        "DEBUG",
        "DEMO_SENSOR_ENABLED",
        "DEMO_SENSOR_INSTANCE",
    ):
        monkeypatch.delenv(name, raising=False)
    app_config.get_settings.cache_clear()
    yield
    app_config.get_settings.cache_clear()


def _set_valid_production_environment(monkeypatch, database_url=None):
    monkeypatch.setenv("ENVIRONMENT", "production")
    monkeypatch.setenv("JWT_SECRET_KEY", "Postgres-Ready!Secret-2026-Qwerty")
    monkeypatch.setenv("CORS_ORIGINS", "https://aqualogic.example")
    monkeypatch.setenv("TRUSTED_HOSTS", "api.aqualogic.example")
    if database_url is None:
        monkeypatch.delenv("DATABASE_URL", raising=False)
    else:
        monkeypatch.setenv("DATABASE_URL", database_url)


def test_development_without_database_url_uses_sqlite(clean_database_environment):
    settings = app_config.get_settings()

    assert settings.environment == "development"
    assert settings.database_url == "sqlite:///./aqualogic.db"


def test_production_without_database_url_is_rejected(clean_database_environment, monkeypatch):
    _set_valid_production_environment(monkeypatch)

    with pytest.raises(ValueError, match="Production requires DATABASE_URL pointing to PostgreSQL"):
        app_config.get_settings()


def test_production_rejects_sqlite_database_url(clean_database_environment, monkeypatch):
    _set_valid_production_environment(monkeypatch, "sqlite:///./aqualogic.db")

    with pytest.raises(ValueError, match="Production DATABASE_URL must use PostgreSQL"):
        app_config.get_settings()


@pytest.mark.parametrize(
    ("database_url", "normalized_url"),
    [
        (
            "postgres://aqua:p%40ss%23@db.example:5432/aqualogic?sslmode=require",
            "postgresql+psycopg2://aqua:p%40ss%23@db.example:5432/aqualogic?sslmode=require",
        ),
        (
            "postgresql://aqua:p%40ss%23@db.example:5432/aqualogic?sslmode=require",
            "postgresql+psycopg2://aqua:p%40ss%23@db.example:5432/aqualogic?sslmode=require",
        ),
        (
            "postgresql+psycopg2://aqua:p%40ss%23@db.example:5432/aqualogic?sslmode=require",
            "postgresql+psycopg2://aqua:p%40ss%23@db.example:5432/aqualogic?sslmode=require",
        ),
        ("sqlite:///path/to/db", "sqlite:///path/to/db"),
    ],
)
def test_normalize_database_url_selects_psycopg2_and_preserves_other_urls(
    database_url, normalized_url
):
    assert app_config.normalize_database_url(database_url) == normalized_url


@pytest.mark.parametrize(
    ("database_url", "normalized_url"),
    [
        (
            "postgres://aqua:p%40ss%23@db.example:5432/aqualogic",
            "postgresql+psycopg2://aqua:p%40ss%23@db.example:5432/aqualogic",
        ),
        (
            "postgresql://aqua:p%40ss%23@db.example:5432/aqualogic",
            "postgresql+psycopg2://aqua:p%40ss%23@db.example:5432/aqualogic",
        ),
        (
            "postgresql+psycopg2://aqua:p%40ss%23@db.example:5432/aqualogic",
            "postgresql+psycopg2://aqua:p%40ss%23@db.example:5432/aqualogic",
        ),
    ],
)
def test_production_accepts_supported_postgresql_urls(
    clean_database_environment,
    monkeypatch,
    database_url,
    normalized_url,
):
    _set_valid_production_environment(monkeypatch, database_url)

    settings = app_config.get_settings()

    assert settings.database_url == normalized_url


@pytest.mark.parametrize(
    "database_url",
    [
        "postgresql://aqua:secret@db.example:not-a-port/aqualogic",
    ],
)
def test_production_rejects_malformed_postgresql_database_urls(
    clean_database_environment, monkeypatch, database_url
):
    _set_valid_production_environment(monkeypatch, database_url)

    with pytest.raises(ValueError, match="Production DATABASE_URL must be a valid PostgreSQL URL"):
        app_config.get_settings()


def test_alembic_config_round_trips_percent_encoded_credentials():
    database_url = "postgresql+psycopg2://aqua:p%40ss%23@db.example:5432/aqualogic"
    alembic_config = Config()

    alembic_config.set_main_option(
        "sqlalchemy.url",
        app_config.escape_alembic_config_url(database_url),
    )

    assert alembic_config.get_main_option("sqlalchemy.url") == database_url

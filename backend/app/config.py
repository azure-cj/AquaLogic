import os
from dataclasses import dataclass
from functools import lru_cache

from sqlalchemy.engine import make_url
from sqlalchemy.exc import ArgumentError

from .services.reading_freshness import READING_FRESHNESS_SECONDS


DEFAULT_JWT_SECRET = "development-only-change-before-production-2026"
MAX_ACCESS_TOKEN_MINUTES = 15
MAX_REFRESH_SESSION_DAYS = 7
DEFAULT_MONITORING_OUTAGE_GRACE_SECONDS = 900
DEFAULT_MONITORING_INCIDENT_CHECK_INTERVAL_SECONDS = 60


def normalize_database_url(database_url: str) -> str:
    """Select psycopg2 explicitly for PostgreSQL URLs."""
    database_url = database_url.strip()
    if database_url.startswith("postgres://"):
        return "postgresql+psycopg2://" + database_url[len("postgres://") :]
    if database_url.startswith("postgresql://"):
        return "postgresql+psycopg2://" + database_url[len("postgresql://") :]
    return database_url


def escape_alembic_config_url(database_url: str) -> str:
    """Escape percent signs for Alembic's ConfigParser interpolation layer."""
    return database_url.replace("%", "%%")


def _parse_bool(value: str | None, default: bool = False) -> bool:
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _parse_csv(value: str | None, default: list[str]) -> list[str]:
    if value is None:
        return default
    return [item.strip() for item in value.split(",") if item.strip()]


@dataclass(frozen=True)
class Settings:
    app_name: str
    environment: str
    debug: bool
    database_url: str
    jwt_secret_key: str
    jwt_issuer: str
    jwt_audience: str
    access_token_expire_minutes: int
    refresh_session_expire_days: int
    cors_origins: list[str]
    trusted_hosts: list[str]
    demo_sensor_enabled: bool
    demo_sensor_instance: bool
    demo_sensor_interval_seconds: int
    public_base_url: str
    public_image_hosts: set[str]
    media_root: str
    max_hero_image_bytes: int
    max_fish_image_bytes: int
    analytics_uptime_warning: float
    analytics_uptime_critical: float
    monitoring_incidents_enabled: bool
    monitoring_outage_grace_seconds: int
    monitoring_incident_check_interval_seconds: int

    @property
    def is_production(self) -> bool:
        return self.environment == "production"

    @property
    def refresh_cookie_secure(self) -> bool:
        return self.is_production


def _validate_production(settings: Settings) -> None:
    if not settings.database_url:
        raise ValueError("Production requires DATABASE_URL pointing to PostgreSQL")
    try:
        database_url = make_url(settings.database_url)
    except (ArgumentError, ValueError):
        raise ValueError("Production DATABASE_URL must be a valid PostgreSQL URL") from None
    if database_url.drivername not in {"postgresql", "postgresql+psycopg2"}:
        raise ValueError(
            "Production DATABASE_URL must use PostgreSQL (postgresql:// or postgresql+psycopg2://)"
        )
    if not database_url.host or not database_url.database:
        raise ValueError("Production DATABASE_URL must include a PostgreSQL host and database name")
    if settings.jwt_secret_key == DEFAULT_JWT_SECRET or len(settings.jwt_secret_key.encode()) < 32:
        raise ValueError("Production requires a non-default JWT_SECRET_KEY of at least 32 bytes")
    if len(set(settings.jwt_secret_key)) < 12:
        raise ValueError("Production JWT_SECRET_KEY must be randomly generated")
    if not settings.cors_origins or "*" in settings.cors_origins:
        raise ValueError("Production requires explicit CORS_ORIGINS")
    if not settings.trusted_hosts or "*" in settings.trusted_hosts:
        raise ValueError("Production requires explicit TRUSTED_HOSTS")
    if settings.debug or settings.demo_sensor_enabled or settings.demo_sensor_instance:
        raise ValueError("Production requires DEBUG and demo generation to be disabled")
    if not 5 <= settings.access_token_expire_minutes <= MAX_ACCESS_TOKEN_MINUTES:
        raise ValueError("ACCESS_TOKEN_EXPIRE_MINUTES must be between 5 and 15 in production")
    if not 1 <= settings.refresh_session_expire_days <= MAX_REFRESH_SESSION_DAYS:
        raise ValueError("REFRESH_SESSION_EXPIRE_DAYS must be between 1 and 7 in production")
    if not settings.monitoring_incidents_enabled:
        raise ValueError("Production requires persistent monitoring incidents to remain enabled")


def _validate_monitoring(settings: Settings) -> None:
    if settings.monitoring_outage_grace_seconds <= READING_FRESHNESS_SECONDS:
        raise ValueError(
            "MONITORING_OUTAGE_GRACE_SECONDS must be strictly greater than the 90-second reading freshness window"
        )
    if settings.monitoring_incident_check_interval_seconds < 1:
        raise ValueError("MONITORING_INCIDENT_CHECK_INTERVAL_SECONDS must be at least 1 second")


@lru_cache
def get_settings() -> Settings:
    environment = os.getenv("ENVIRONMENT", "development").strip().lower()
    configured_database_url = os.getenv("DATABASE_URL")
    if configured_database_url is None:
        database_url = "" if environment == "production" else "sqlite:///./aqualogic.db"
    else:
        database_url = normalize_database_url(configured_database_url)
    settings = Settings(
        app_name=os.getenv("APP_NAME", "AquaLogic API"),
        environment=environment,
        debug=_parse_bool(os.getenv("DEBUG")),
        database_url=database_url,
        jwt_secret_key=os.getenv("JWT_SECRET_KEY", DEFAULT_JWT_SECRET),
        jwt_issuer=os.getenv("JWT_ISSUER", "aqualogic-api"),
        jwt_audience=os.getenv("JWT_AUDIENCE", "aqualogic-web"),
        access_token_expire_minutes=int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "15")),
        refresh_session_expire_days=int(os.getenv("REFRESH_SESSION_EXPIRE_DAYS", "7")),
        cors_origins=_parse_csv(os.getenv("CORS_ORIGINS"), ["http://localhost:5173"]),
        trusted_hosts=_parse_csv(os.getenv("TRUSTED_HOSTS"), ["localhost", "127.0.0.1", "testserver"]),
        demo_sensor_enabled=_parse_bool(os.getenv("DEMO_SENSOR_ENABLED")),
        demo_sensor_instance=_parse_bool(os.getenv("DEMO_SENSOR_INSTANCE")),
        demo_sensor_interval_seconds=int(os.getenv("DEMO_SENSOR_INTERVAL_SECONDS", "30")),
        public_base_url=os.getenv("PUBLIC_BASE_URL", "http://localhost:5173").rstrip("/"),
        public_image_hosts=set(_parse_csv(os.getenv("PUBLIC_IMAGE_HOSTS"), ["images.unsplash.com"] if environment != "production" else [])),
        media_root=os.getenv("MEDIA_ROOT", "./media"),
        max_hero_image_bytes=int(os.getenv("MAX_HERO_IMAGE_BYTES", str(5 * 1024 * 1024))),
        max_fish_image_bytes=int(os.getenv("MAX_FISH_IMAGE_BYTES", os.getenv("MAX_HERO_IMAGE_BYTES", str(5 * 1024 * 1024)))),
        analytics_uptime_warning=float(os.getenv("ANALYTICS_UPTIME_WARNING", "99")),
        analytics_uptime_critical=float(os.getenv("ANALYTICS_UPTIME_CRITICAL", "95")),
        monitoring_incidents_enabled=_parse_bool(os.getenv("MONITORING_INCIDENTS_ENABLED"), True),
        monitoring_outage_grace_seconds=int(
            os.getenv("MONITORING_OUTAGE_GRACE_SECONDS", str(DEFAULT_MONITORING_OUTAGE_GRACE_SECONDS))
        ),
        monitoring_incident_check_interval_seconds=int(
            os.getenv(
                "MONITORING_INCIDENT_CHECK_INTERVAL_SECONDS",
                str(DEFAULT_MONITORING_INCIDENT_CHECK_INTERVAL_SECONDS),
            )
        ),
    )
    _validate_monitoring(settings)
    if settings.is_production:
        _validate_production(settings)
    return settings


settings = get_settings()

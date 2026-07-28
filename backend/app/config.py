import os
from dataclasses import dataclass
from functools import lru_cache


DEFAULT_JWT_SECRET = "development-only-change-before-production-2026"
MAX_ACCESS_TOKEN_MINUTES = 15
MAX_REFRESH_SESSION_DAYS = 7


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
    analytics_uptime_warning: float
    analytics_uptime_critical: float

    @property
    def is_production(self) -> bool:
        return self.environment == "production"

    @property
    def refresh_cookie_secure(self) -> bool:
        return self.is_production


def _validate_production(settings: Settings) -> None:
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


@lru_cache
def get_settings() -> Settings:
    environment = os.getenv("ENVIRONMENT", "development").strip().lower()
    settings = Settings(
        app_name=os.getenv("APP_NAME", "AquaLogic API"),
        environment=environment,
        debug=_parse_bool(os.getenv("DEBUG")),
        database_url=os.getenv("DATABASE_URL", "sqlite:///./aqualogic.db"),
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
        analytics_uptime_warning=float(os.getenv("ANALYTICS_UPTIME_WARNING", "99")),
        analytics_uptime_critical=float(os.getenv("ANALYTICS_UPTIME_CRITICAL", "95")),
    )
    if settings.is_production:
        _validate_production(settings)
    return settings


settings = get_settings()

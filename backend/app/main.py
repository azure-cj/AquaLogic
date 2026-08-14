import uuid
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from fastapi.openapi.docs import get_swagger_ui_html
from fastapi.openapi.utils import get_openapi
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from starlette.responses import Response
from starlette.middleware.trustedhost import TrustedHostMiddleware
from swagger_ui_bundle import swagger_ui_path

from .config import settings
from .database import Base, engine
from .routes import alerts, auth, dashboard, devices, fish, management, public, security, sensors, species_suitability, tanks
from .services.decision_engine import ensure_default_thresholds
from .services.demo_sensor import start_demo_generator

# Ensure all SQLAlchemy models are registered before metadata is used.
from . import models  # noqa: F401


@asynccontextmanager
async def lifespan(_: FastAPI):
    # Production schema ownership belongs to Alembic. This local convenience is opt-in only.
    if not settings.is_production:
        Base.metadata.create_all(bind=engine)
        from .database import SessionLocal

        db = SessionLocal()
        try:
            ensure_default_thresholds(db)
        finally:
            db.close()
    start_demo_generator()
    yield


app = FastAPI(
    title=settings.app_name,
    debug=settings.debug,
    lifespan=lifespan,
    docs_url=None,
)
# swagger-ui-bundle ships a Swagger UI release that supports OpenAPI 3.0.x.
# FastAPI 0.140 sets this as an app attribute rather than constructor option.
app.openapi_version = "3.0.3"


def _openapi_schema() -> dict:
    """Describe the existing Authorization header as bearer auth in Swagger.

    Runtime authentication still uses the project's OAuth2PasswordBearer
    extractor. The login endpoint intentionally accepts JSON, so advertising an
    OAuth password flow made Swagger send an incompatible form request.
    """
    if app.openapi_schema:
        return app.openapi_schema
    schema = get_openapi(
        title=app.title,
        version=app.version,
        openapi_version=app.openapi_version,
        routes=app.routes,
    )
    schemes = schema.setdefault("components", {}).setdefault("securitySchemes", {})
    schemes["OAuth2PasswordBearer"] = {
        "type": "http",
        "scheme": "bearer",
        "bearerFormat": "JWT",
    }
    app.openapi_schema = schema
    return schema


app.openapi = _openapi_schema
app.mount("/static/swagger-ui", StaticFiles(directory=swagger_ui_path), name="swagger-ui")
app.add_middleware(TrustedHostMiddleware, allowed_hosts=settings.trusted_hosts)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
)


def _content_security_policy() -> str:
    image_sources = ["'self'", "data:", *[f"https://{host}" for host in sorted(settings.public_image_hosts)]]
    return "; ".join(
        (
            "default-src 'self'",
            "base-uri 'none'",
            "object-src 'none'",
            "frame-ancestors 'none'",
            "script-src 'self'",
            "connect-src 'self'",
            "font-src 'self'",
            f"img-src {' '.join(image_sources)}",
            "style-src-elem 'self'",
            "style-src-attr 'unsafe-inline'",
        )
    )


def _apply_security_headers(request: Request, response: Response) -> Response:
    response.headers["X-Request-ID"] = request.state.request_id
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=(), payment=(), usb=()"
    # FastAPI's Swagger HTML contains one small inline initializer. Keep the
    # application policy strict and relax this only for the local API docs page.
    response.headers["Content-Security-Policy"] = (
        "default-src 'self'; base-uri 'none'; object-src 'none'; frame-ancestors 'none'; "
        "script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; "
        "img-src 'self' data:; font-src 'self'; connect-src 'self'"
        if request.url.path == "/docs"
        else _content_security_policy()
    )
    if settings.is_production:
        response.headers["Strict-Transport-Security"] = "max-age=31536000"
    if request.url.path.startswith("/auth/") or request.headers.get("authorization"):
        response.headers["Cache-Control"] = "no-store"
    return response


@app.middleware("http")
async def security_headers_and_body_limit(request: Request, call_next):
    request.state.request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))[:64]
    content_length = request.headers.get("content-length")
    try:
        declared_size = int(content_length) if content_length else 0
    except ValueError:
        return _apply_security_headers(request, JSONResponse(status_code=400, content={"detail": "Invalid Content-Length"}))
    if declared_size > 64 * 1024:
        return _apply_security_headers(request, JSONResponse(status_code=413, content={"detail": "Request body is too large"}))
    if request.method in {"POST", "PUT", "PATCH", "DELETE"}:
        body = await request.body()
        if len(body) > 64 * 1024:
            return _apply_security_headers(request, JSONResponse(status_code=413, content={"detail": "Request body is too large"}))
    response = await call_next(request)
    return _apply_security_headers(request, response)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/docs", include_in_schema=False)
def swagger_docs():
    """Serve API documentation without relying on a browser-accessible CDN."""
    return get_swagger_ui_html(
        openapi_url=app.openapi_url,
        title=f"{settings.app_name} - Swagger UI",
        swagger_js_url="/static/swagger-ui/swagger-ui-bundle.js",
        swagger_css_url="/static/swagger-ui/swagger-ui.css",
    )


app.include_router(auth.router)
app.include_router(tanks.router)
app.include_router(species_suitability.router)
app.include_router(fish.router)
app.include_router(sensors.router)
app.include_router(devices.router)
app.include_router(alerts.router)
app.include_router(public.router)
app.include_router(management.router)
app.include_router(dashboard.router)
app.include_router(security.router)

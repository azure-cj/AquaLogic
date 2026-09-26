from datetime import datetime

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    JSON,
    String,
    UniqueConstraint,
    func,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class PushNotificationEvent(Base):
    """One logical, idempotently-created operational notification."""

    __tablename__ = "push_notification_events"
    __table_args__ = (
        UniqueConstraint("event_key", name="uq_push_notification_events_event_key"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    event_key: Mapped[str] = mapped_column(String(200), nullable=False)
    event_type: Mapped[str] = mapped_column(String(40), nullable=False)
    source_type: Mapped[str] = mapped_column(String(40), nullable=False)
    source_id: Mapped[str] = mapped_column(String(80), nullable=False)
    tank_id: Mapped[int | None] = mapped_column(
        ForeignKey("tanks.id", ondelete="SET NULL"), nullable=True, index=True
    )
    title: Mapped[str] = mapped_column(String(160), nullable=False)
    body: Mapped[str] = mapped_column(String(300), nullable=False)
    payload: Mapped[dict[str, str]] = mapped_column(JSON, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class PushNotificationDelivery(Base):
    """One retryable delivery attempt chain for an event and device."""

    __tablename__ = "push_notification_deliveries"
    __table_args__ = (
        UniqueConstraint(
            "event_id", "push_device_id", name="uq_push_notification_deliveries_event_device"
        ),
        CheckConstraint(
            "status IN ('pending', 'sending', 'retry', 'sent', 'permanent_failed', 'skipped')",
            name="ck_push_notification_deliveries_status",
        ),
        CheckConstraint("attempt_count >= 0", name="ck_push_notification_deliveries_attempt_count"),
        Index("ix_push_notification_deliveries_due", "status", "next_attempt_at"),
        Index("ix_push_notification_deliveries_lease", "status", "locked_at"),
        Index("ix_push_notification_deliveries_device", "push_device_id"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    event_id: Mapped[int] = mapped_column(
        ForeignKey("push_notification_events.id", ondelete="CASCADE"), nullable=False
    )
    push_device_id: Mapped[int] = mapped_column(
        ForeignKey("push_devices.id", ondelete="CASCADE"), nullable=False
    )
    status: Mapped[str] = mapped_column(
        String(24), nullable=False, default="pending", server_default=text("'pending'")
    )
    attempt_count: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default=text("0")
    )
    next_attempt_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    locked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    lock_token: Mapped[str | None] = mapped_column(String(36), nullable=True)
    firebase_message_id: Mapped[str | None] = mapped_column(String(256), nullable=True)
    last_error_code: Mapped[str | None] = mapped_column(String(80), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
    sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

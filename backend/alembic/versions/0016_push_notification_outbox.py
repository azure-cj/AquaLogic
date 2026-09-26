"""Add durable push notification events and per-device deliveries.

Revision ID: 0016_push_notification_outbox
Revises: 0015_authenticated_push_devices
"""

from alembic import op
import sqlalchemy as sa


revision = "0016_push_notification_outbox"
down_revision = "0015_authenticated_push_devices"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "push_notification_events",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("event_key", sa.String(length=200), nullable=False),
        sa.Column("event_type", sa.String(length=40), nullable=False),
        sa.Column("source_type", sa.String(length=40), nullable=False),
        sa.Column("source_id", sa.String(length=80), nullable=False),
        sa.Column(
            "tank_id",
            sa.Integer(),
            sa.ForeignKey("tanks.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("title", sa.String(length=160), nullable=False),
        sa.Column("body", sa.String(length=300), nullable=False),
        sa.Column("payload", sa.JSON(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.UniqueConstraint("event_key", name="uq_push_notification_events_event_key"),
    )
    op.create_index("ix_push_notification_events_tank_id", "push_notification_events", ["tank_id"])

    op.create_table(
        "push_notification_deliveries",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "event_id",
            sa.Integer(),
            sa.ForeignKey("push_notification_events.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "push_device_id",
            sa.Integer(),
            sa.ForeignKey("push_devices.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("status", sa.String(length=24), server_default=sa.text("'pending'"), nullable=False),
        sa.Column("attempt_count", sa.Integer(), server_default=sa.text("0"), nullable=False),
        sa.Column(
            "next_attempt_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column("locked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("lock_token", sa.String(length=36), nullable=True),
        sa.Column("firebase_message_id", sa.String(length=256), nullable=True),
        sa.Column("last_error_code", sa.String(length=80), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column("sent_at", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint(
            "event_id", "push_device_id", name="uq_push_notification_deliveries_event_device"
        ),
        sa.CheckConstraint(
            "status IN ('pending', 'sending', 'retry', 'sent', 'permanent_failed', 'skipped')",
            name="ck_push_notification_deliveries_status",
        ),
        sa.CheckConstraint("attempt_count >= 0", name="ck_push_notification_deliveries_attempt_count"),
    )
    op.create_index(
        "ix_push_notification_deliveries_due",
        "push_notification_deliveries",
        ["status", "next_attempt_at"],
    )
    op.create_index(
        "ix_push_notification_deliveries_lease",
        "push_notification_deliveries",
        ["status", "locked_at"],
    )
    op.create_index(
        "ix_push_notification_deliveries_device",
        "push_notification_deliveries",
        ["push_device_id"],
    )


def downgrade() -> None:
    op.drop_index("ix_push_notification_deliveries_device", table_name="push_notification_deliveries")
    op.drop_index("ix_push_notification_deliveries_lease", table_name="push_notification_deliveries")
    op.drop_index("ix_push_notification_deliveries_due", table_name="push_notification_deliveries")
    op.drop_table("push_notification_deliveries")
    op.drop_index("ix_push_notification_events_tank_id", table_name="push_notification_events")
    op.drop_table("push_notification_events")

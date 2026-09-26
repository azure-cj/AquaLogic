"""Add authenticated Android push-device registrations.

Revision ID: 0015_authenticated_push_devices
Revises: 0014_tank_threshold_overrides
"""

from alembic import op
import sqlalchemy as sa


revision = "0015_authenticated_push_devices"
down_revision = "0014_tank_threshold_overrides"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "push_devices",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "auth_session_id",
            sa.String(length=36),
            sa.ForeignKey("auth_sessions.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("installation_id", sa.String(length=36), nullable=False),
        sa.Column("fcm_token", sa.String(length=4096), nullable=False),
        sa.Column("platform", sa.String(length=16), nullable=False),
        sa.Column("is_active", sa.Boolean(), server_default=sa.true(), nullable=False),
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
        sa.Column(
            "last_registered_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column("disabled_at", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint(
            "installation_id", name="uq_push_devices_installation_id"
        ),
        sa.UniqueConstraint("fcm_token", name="uq_push_devices_fcm_token"),
    )
    op.create_index("ix_push_devices_user_id", "push_devices", ["user_id"])
    op.create_index(
        "ix_push_devices_auth_session_id", "push_devices", ["auth_session_id"]
    )


def downgrade() -> None:
    op.drop_index("ix_push_devices_auth_session_id", table_name="push_devices")
    op.drop_index("ix_push_devices_user_id", table_name="push_devices")
    op.drop_table("push_devices")

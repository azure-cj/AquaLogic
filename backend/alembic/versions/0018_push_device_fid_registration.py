"""Track FCM registration separately from the stored Firebase Installation ID.

Revision ID: 0018_push_device_fid_registration
Revises: 0017_push_device_firebase_installation_id
"""

from alembic import op
import sqlalchemy as sa


revision = "0018_push_device_fid_registration"
down_revision = "0017_push_device_firebase_installation_id"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("push_devices") as batch_op:
        batch_op.add_column(
            sa.Column(
                "firebase_installation_id_registered",
                sa.Boolean(),
                server_default=sa.false(),
                nullable=False,
            )
        )
        batch_op.alter_column(
            "fcm_token",
            existing_type=sa.String(length=4096),
            nullable=True,
        )


def downgrade() -> None:
    bind = op.get_bind()
    has_fid_only_devices = bind.execute(
        sa.text("SELECT 1 FROM push_devices WHERE fcm_token IS NULL LIMIT 1")
    ).first()
    if has_fid_only_devices is not None:
        raise RuntimeError(
            "Cannot downgrade while FID-only push-device registrations exist"
        )

    with op.batch_alter_table("push_devices") as batch_op:
        batch_op.alter_column(
            "fcm_token",
            existing_type=sa.String(length=4096),
            nullable=False,
        )
        batch_op.drop_column("firebase_installation_id_registered")

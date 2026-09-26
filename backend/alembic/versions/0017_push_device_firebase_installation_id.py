"""Store Firebase Installation IDs separately from FCM tokens.

Revision ID: 0017_push_device_firebase_installation_id
Revises: 0016_push_notification_outbox
"""

from alembic import op
import sqlalchemy as sa


revision = "0017_push_device_firebase_installation_id"
down_revision = "0016_push_notification_outbox"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Nullable preserves existing M6.2 rows until an updated client registers.
    with op.batch_alter_table("push_devices") as batch_op:
        batch_op.add_column(
            sa.Column("firebase_installation_id", sa.String(length=128), nullable=True)
        )
        batch_op.create_unique_constraint(
            "uq_push_devices_firebase_installation_id",
            ["firebase_installation_id"],
        )


def downgrade() -> None:
    with op.batch_alter_table("push_devices") as batch_op:
        batch_op.drop_constraint(
            "uq_push_devices_firebase_installation_id",
            type_="unique",
        )
        batch_op.drop_column("firebase_installation_id")

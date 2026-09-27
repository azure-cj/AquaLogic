"""Add device-scoped idempotency IDs to sensor readings.

Revision ID: 0019_sensor_reading_sample_id
Revises: 0018_push_device_fid_registration
"""

from alembic import op
import sqlalchemy as sa


revision = "0019_sensor_reading_sample_id"
down_revision = "0018_push_device_fid_registration"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("sensor_readings") as batch_op:
        batch_op.add_column(sa.Column("sample_id", sa.String(length=36), nullable=True))
        batch_op.create_unique_constraint(
            "uq_sensor_readings_device_sample_id",
            ["device_id", "sample_id"],
        )


def downgrade() -> None:
    with op.batch_alter_table("sensor_readings") as batch_op:
        batch_op.drop_constraint(
            "uq_sensor_readings_device_sample_id",
            type_="unique",
        )
        batch_op.drop_column("sample_id")

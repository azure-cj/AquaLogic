"""Add bridge devices and nullable fields for uninstalled sensors.

Revision ID: 0007_esp32_bridge_devices
Revises: 0006_auth_security_hardening
"""
from alembic import op
import sqlalchemy as sa


revision = "0007_esp32_bridge_devices"
down_revision = "0006_auth_security_hardening"
branch_labels = None
depends_on = None


def upgrade() -> None:
    connection = op.get_bind()
    inspector = sa.inspect(connection)
    tables = set(inspector.get_table_names())
    if "registered_devices" not in tables:
        op.create_table(
            "registered_devices",
            sa.Column("id", sa.String(length=64), primary_key=True),
            sa.Column("tank_id", sa.Integer(), sa.ForeignKey("tanks.id", ondelete="CASCADE"), nullable=False),
            sa.Column("key_hash", sa.String(length=64), nullable=False, unique=True),
            sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=True),
        )
        op.create_index("ix_registered_devices_tank_id", "registered_devices", ["tank_id"])
    columns = {column["name"] for column in inspector.get_columns("sensor_readings")}
    if {"dissolved_oxygen", "ammonia"}.issubset(columns):
        with op.batch_alter_table("sensor_readings") as batch:
            batch.alter_column("dissolved_oxygen", existing_type=sa.Float(), nullable=True)
            batch.alter_column("ammonia", existing_type=sa.Float(), nullable=True)


def downgrade() -> None:
    with op.batch_alter_table("sensor_readings") as batch:
        batch.alter_column("dissolved_oxygen", existing_type=sa.Float(), nullable=False)
        batch.alter_column("ammonia", existing_type=sa.Float(), nullable=False)
    op.drop_index("ix_registered_devices_tank_id", table_name="registered_devices")
    op.drop_table("registered_devices")

"""Add sensor reading provenance and server receipt timestamps.

Revision ID: 0009_domain_foundation
Revises: 0008_actuator_controls
"""

from alembic import op
import sqlalchemy as sa


revision = "0009_domain_foundation"
down_revision = "0008_actuator_controls"
branch_labels = None
depends_on = None


def upgrade() -> None:
    connection = op.get_bind()
    is_sqlite = connection.dialect.name == "sqlite"
    inspector = sa.inspect(connection)
    columns = {column["name"] for column in inspector.get_columns("sensor_readings")}

    missing_device_id = "device_id" not in columns
    missing_received_at = "received_at" not in columns
    if is_sqlite and (missing_device_id or missing_received_at):
        with op.batch_alter_table("sensor_readings", recreate="always") as batch:
            if missing_device_id:
                batch.add_column(sa.Column("device_id", sa.String(length=64), nullable=True))
                batch.create_foreign_key(
                    "fk_sensor_readings_device_id_registered_devices",
                    "registered_devices",
                    ["device_id"],
                    ["id"],
                    ondelete="SET NULL",
                )
            if missing_received_at:
                batch.add_column(sa.Column("received_at", sa.DateTime(timezone=True), nullable=True))
    elif not is_sqlite:
        if missing_device_id:
            op.add_column("sensor_readings", sa.Column("device_id", sa.String(length=64), nullable=True))
            op.create_foreign_key(
                "fk_sensor_readings_device_id_registered_devices",
                "sensor_readings",
                "registered_devices",
                ["device_id"],
                ["id"],
                ondelete="SET NULL",
            )
        if missing_received_at:
            op.add_column(
                "sensor_readings",
                sa.Column("received_at", sa.DateTime(timezone=True), nullable=True),
            )

    op.execute(sa.text("UPDATE sensor_readings SET received_at = timestamp WHERE received_at IS NULL"))
    if is_sqlite:
        with op.batch_alter_table("sensor_readings", recreate="always") as batch:
            batch.alter_column(
                "received_at",
                existing_type=sa.DateTime(timezone=True),
                nullable=False,
                server_default=sa.text("CURRENT_TIMESTAMP"),
            )
    else:
        op.alter_column(
            "sensor_readings",
            "received_at",
            existing_type=sa.DateTime(timezone=True),
            existing_nullable=True,
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        )

    index_names = {index["name"] for index in sa.inspect(connection).get_indexes("sensor_readings")}
    if "ix_sensor_readings_device_id" not in index_names:
        op.create_index("ix_sensor_readings_device_id", "sensor_readings", ["device_id"])
    if "ix_sensor_readings_received_at" not in index_names:
        op.create_index("ix_sensor_readings_received_at", "sensor_readings", ["received_at"])


def downgrade() -> None:
    connection = op.get_bind()
    is_sqlite = connection.dialect.name == "sqlite"
    index_names = {index["name"] for index in sa.inspect(connection).get_indexes("sensor_readings")}
    if "ix_sensor_readings_received_at" in index_names:
        op.drop_index("ix_sensor_readings_received_at", table_name="sensor_readings")
    if "ix_sensor_readings_device_id" in index_names:
        op.drop_index("ix_sensor_readings_device_id", table_name="sensor_readings")
    if is_sqlite:
        with op.batch_alter_table("sensor_readings", recreate="always") as batch:
            batch.drop_column("received_at")
            batch.drop_column("device_id")
    else:
        foreign_keys = {
            foreign_key.get("name")
            for foreign_key in sa.inspect(connection).get_foreign_keys("sensor_readings")
        }
        if "fk_sensor_readings_device_id_registered_devices" in foreign_keys:
            op.drop_constraint(
                "fk_sensor_readings_device_id_registered_devices",
                "sensor_readings",
                type_="foreignkey",
            )
        op.drop_column("sensor_readings", "received_at")
        op.drop_column("sensor_readings", "device_id")

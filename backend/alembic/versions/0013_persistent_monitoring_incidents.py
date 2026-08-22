"""Persist tank-level unattended monitoring incidents.

Revision ID: 0013_persistent_monitoring_incidents
Revises: 0012_retired_tank_lifecycle
"""

from alembic import op
import sqlalchemy as sa


revision = "0013_persistent_monitoring_incidents"
down_revision = "0012_retired_tank_lifecycle"
branch_labels = None
depends_on = None


def upgrade() -> None:
    connection = op.get_bind()
    inspector = sa.inspect(connection)
    if "monitoring_incidents" not in inspector.get_table_names():
        op.create_table(
            "monitoring_incidents",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column(
                "tank_id",
                sa.Integer(),
                sa.ForeignKey("tanks.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("detected_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("last_reading_received_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("resolved_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("resolution_reason", sa.String(length=32), nullable=True),
            sa.Column(
                "recovery_reading_id",
                sa.Integer(),
                sa.ForeignKey("sensor_readings.id", ondelete="SET NULL"),
                nullable=True,
            ),
        )

    indexes = {index["name"] for index in sa.inspect(connection).get_indexes("monitoring_incidents")}
    for name, columns in (
        ("ix_monitoring_incidents_id", ["id"]),
        ("ix_monitoring_incidents_tank_id", ["tank_id"]),
        ("ix_monitoring_incidents_started_at", ["started_at"]),
        ("ix_monitoring_incidents_detected_at", ["detected_at"]),
        ("ix_monitoring_incidents_resolved_at", ["resolved_at"]),
        ("ix_monitoring_incidents_resolution_reason", ["resolution_reason"]),
        ("ix_monitoring_incidents_recovery_reading_id", ["recovery_reading_id"]),
    ):
        if name not in indexes:
            op.create_index(name, "monitoring_incidents", columns)
    if "uq_monitoring_incidents_active_tank" not in indexes:
        op.create_index(
            "uq_monitoring_incidents_active_tank",
            "monitoring_incidents",
            ["tank_id"],
            unique=True,
            sqlite_where=sa.text("resolved_at IS NULL"),
            postgresql_where=sa.text("resolved_at IS NULL"),
        )


def downgrade() -> None:
    connection = op.get_bind()
    indexes = {index["name"] for index in sa.inspect(connection).get_indexes("monitoring_incidents")}
    for name in (
        "uq_monitoring_incidents_active_tank",
        "ix_monitoring_incidents_recovery_reading_id",
        "ix_monitoring_incidents_resolution_reason",
        "ix_monitoring_incidents_resolved_at",
        "ix_monitoring_incidents_detected_at",
        "ix_monitoring_incidents_started_at",
        "ix_monitoring_incidents_tank_id",
        "ix_monitoring_incidents_id",
    ):
        if name in indexes:
            op.drop_index(name, table_name="monitoring_incidents")
    if "monitoring_incidents" in sa.inspect(connection).get_table_names():
        op.drop_table("monitoring_incidents")

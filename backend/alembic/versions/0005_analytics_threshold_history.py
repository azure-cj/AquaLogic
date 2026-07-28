"""Add analytics threshold history and query indexes.

Revision ID: 0005_analytics_threshold_history
Revises: 0004_fish_species_directory
"""

from alembic import op
import sqlalchemy as sa


revision = "0005_analytics_threshold_history"
down_revision = "0004_fish_species_directory"
branch_labels = None
depends_on = None


def upgrade() -> None:
    connection = op.get_bind()
    inspector = sa.inspect(connection)
    if "threshold_revisions" not in inspector.get_table_names():
        op.create_table(
            "threshold_revisions",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("parameter", sa.String(length=50), nullable=False),
            sa.Column("unit", sa.String(length=30), nullable=False),
            sa.Column("warning_min", sa.Float(), nullable=True),
            sa.Column("warning_max", sa.Float(), nullable=True),
            sa.Column("critical_min", sa.Float(), nullable=True),
            sa.Column("critical_max", sa.Float(), nullable=True),
            sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.true()),
            sa.Column("effective_from", sa.DateTime(timezone=True), nullable=False),
        )

    def ensure_index(name: str, table: str, columns: list[str]) -> None:
        existing = {item["name"] for item in sa.inspect(connection).get_indexes(table)}
        if name not in existing:
            op.create_index(name, table, columns)

    ensure_index(
        "ix_threshold_revisions_parameter_effective",
        "threshold_revisions",
        ["parameter", "effective_from"],
    )
    ensure_index(
        "ix_sensor_readings_tank_timestamp",
        "sensor_readings",
        ["tank_id", "timestamp"],
    )
    ensure_index(
        "ix_alerts_created_parameter_tank",
        "alerts",
        ["created_at", "parameter", "tank_id"],
    )
    connection.execute(
        sa.text(
            """
            INSERT INTO threshold_revisions (
                parameter, unit, warning_min, warning_max,
                critical_min, critical_max, enabled, effective_from
            )
            SELECT
                parameter, unit, warning_min, warning_max,
                critical_min, critical_max, enabled,
                COALESCE(
                    (SELECT MIN(timestamp) FROM sensor_readings),
                    updated_at,
                    CURRENT_TIMESTAMP
                )
            FROM threshold_configs
            WHERE NOT EXISTS (
                SELECT 1
                FROM threshold_revisions revision
                WHERE revision.parameter = threshold_configs.parameter
            )
            """
        )
    )


def downgrade() -> None:
    op.drop_index("ix_alerts_created_parameter_tank", table_name="alerts")
    op.drop_index("ix_sensor_readings_tank_timestamp", table_name="sensor_readings")
    op.drop_index(
        "ix_threshold_revisions_parameter_effective",
        table_name="threshold_revisions",
    )
    op.drop_table("threshold_revisions")

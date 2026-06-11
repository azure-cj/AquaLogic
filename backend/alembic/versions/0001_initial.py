"""Initial schema for AquaLogic backend

Revision ID: 0001_initial
Revises:
Create Date: 2026-04-26 00:00:00
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "0001_initial"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("email", sa.String(length=255), nullable=False),
        sa.Column("hashed_password", sa.String(length=255), nullable=False),
        sa.Column("role", sa.String(length=50), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_users_email"), "users", ["email"], unique=True)
    op.create_index(op.f("ix_users_id"), "users", ["id"], unique=False)

    op.create_table(
        "tanks",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("name", sa.String(length=100), nullable=False),
        sa.Column("location", sa.String(length=150), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("name"),
    )
    op.create_index(op.f("ix_tanks_id"), "tanks", ["id"], unique=False)

    op.create_table(
        "fish_species",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("common_name", sa.String(length=100), nullable=False),
        sa.Column("scientific_name", sa.String(length=150), nullable=False),
        sa.Column("photo_url", sa.String(length=500), nullable=True),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("ideal_temp_min", sa.Float(), nullable=True),
        sa.Column("ideal_temp_max", sa.Float(), nullable=True),
        sa.Column("ideal_ph_min", sa.Float(), nullable=True),
        sa.Column("ideal_ph_max", sa.Float(), nullable=True),
        sa.Column("ideal_do_min", sa.Float(), nullable=True),
        sa.Column("ideal_tds_min", sa.Float(), nullable=True),
        sa.Column("ideal_tds_max", sa.Float(), nullable=True),
        sa.Column("diet", sa.Text(), nullable=True),
        sa.Column("compatibility_notes", sa.Text(), nullable=True),
        sa.Column("care_tips", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_fish_species_common_name"), "fish_species", ["common_name"], unique=False)
    op.create_index(op.f("ix_fish_species_id"), "fish_species", ["id"], unique=False)

    op.create_table(
        "tank_fish",
        sa.Column("tank_id", sa.Integer(), nullable=False),
        sa.Column("fish_species_id", sa.Integer(), nullable=False),
        sa.Column("added_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["fish_species_id"], ["fish_species.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["tank_id"], ["tanks.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("tank_id", "fish_species_id"),
    )

    op.create_table(
        "sensor_readings",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("tank_id", sa.Integer(), nullable=False),
        sa.Column("timestamp", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("temperature", sa.Float(), nullable=False),
        sa.Column("ph", sa.Float(), nullable=False),
        sa.Column("turbidity", sa.Float(), nullable=False),
        sa.Column("dissolved_oxygen", sa.Float(), nullable=False),
        sa.Column("tds", sa.Float(), nullable=False),
        sa.Column("ammonia", sa.Float(), nullable=False),
        sa.Column("is_mock", sa.Boolean(), nullable=False),
        sa.ForeignKeyConstraint(["tank_id"], ["tanks.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_sensor_readings_id"), "sensor_readings", ["id"], unique=False)
    op.create_index(op.f("ix_sensor_readings_tank_id"), "sensor_readings", ["tank_id"], unique=False)
    op.create_index(op.f("ix_sensor_readings_timestamp"), "sensor_readings", ["timestamp"], unique=False)

    op.create_table(
        "alerts",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("tank_id", sa.Integer(), nullable=False),
        sa.Column("reading_id", sa.Integer(), nullable=True),
        sa.Column("parameter", sa.String(length=50), nullable=False),
        sa.Column(
            "severity",
            sa.Enum("warning", "critical", name="alertseverity", native_enum=False),
            nullable=False,
        ),
        sa.Column("message", sa.Text(), nullable=False),
        sa.Column("is_resolved", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["reading_id"], ["sensor_readings.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["tank_id"], ["tanks.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_alerts_id"), "alerts", ["id"], unique=False)
    op.create_index(op.f("ix_alerts_is_resolved"), "alerts", ["is_resolved"], unique=False)
    op.create_index(op.f("ix_alerts_parameter"), "alerts", ["parameter"], unique=False)
    op.create_index(op.f("ix_alerts_reading_id"), "alerts", ["reading_id"], unique=False)
    op.create_index(op.f("ix_alerts_tank_id"), "alerts", ["tank_id"], unique=False)


def downgrade() -> None:
    op.drop_index(op.f("ix_alerts_tank_id"), table_name="alerts")
    op.drop_index(op.f("ix_alerts_reading_id"), table_name="alerts")
    op.drop_index(op.f("ix_alerts_parameter"), table_name="alerts")
    op.drop_index(op.f("ix_alerts_is_resolved"), table_name="alerts")
    op.drop_index(op.f("ix_alerts_id"), table_name="alerts")
    op.drop_table("alerts")

    op.drop_index(op.f("ix_sensor_readings_timestamp"), table_name="sensor_readings")
    op.drop_index(op.f("ix_sensor_readings_tank_id"), table_name="sensor_readings")
    op.drop_index(op.f("ix_sensor_readings_id"), table_name="sensor_readings")
    op.drop_table("sensor_readings")

    op.drop_table("tank_fish")

    op.drop_index(op.f("ix_fish_species_id"), table_name="fish_species")
    op.drop_index(op.f("ix_fish_species_common_name"), table_name="fish_species")
    op.drop_table("fish_species")

    op.drop_index(op.f("ix_tanks_id"), table_name="tanks")
    op.drop_table("tanks")

    op.drop_index(op.f("ix_users_id"), table_name="users")
    op.drop_index(op.f("ix_users_email"), table_name="users")
    op.drop_table("users")

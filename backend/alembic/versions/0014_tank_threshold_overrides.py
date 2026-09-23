"""Add optional per-tank threshold overrides and history.

Revision ID: 0014_tank_threshold_overrides
Revises: 0013_persistent_monitoring_incidents
"""

from alembic import op
import sqlalchemy as sa


revision = "0014_tank_threshold_overrides"
down_revision = "0013_persistent_monitoring_incidents"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "tank_threshold_overrides",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "tank_id",
            sa.Integer(),
            sa.ForeignKey("tanks.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("parameter", sa.String(length=50), nullable=False),
        sa.Column("unit", sa.String(length=30), nullable=False),
        sa.Column("warning_min", sa.Float(), nullable=True),
        sa.Column("warning_max", sa.Float(), nullable=True),
        sa.Column("critical_min", sa.Float(), nullable=True),
        sa.Column("critical_max", sa.Float(), nullable=True),
        sa.Column("enabled", sa.Boolean(), nullable=False),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.UniqueConstraint(
            "tank_id", "parameter", name="uq_tank_threshold_override_parameter"
        ),
    )
    op.create_table(
        "tank_threshold_revisions",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "tank_id",
            sa.Integer(),
            sa.ForeignKey("tanks.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("parameter", sa.String(length=50), nullable=False),
        sa.Column("is_override", sa.Boolean(), nullable=False),
        sa.Column("unit", sa.String(length=30), nullable=True),
        sa.Column("warning_min", sa.Float(), nullable=True),
        sa.Column("warning_max", sa.Float(), nullable=True),
        sa.Column("critical_min", sa.Float(), nullable=True),
        sa.Column("critical_max", sa.Float(), nullable=True),
        sa.Column("enabled", sa.Boolean(), nullable=True),
        sa.Column(
            "effective_from",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index(
        "ix_tank_threshold_revisions_tank_parameter_effective",
        "tank_threshold_revisions",
        ["tank_id", "parameter", "effective_from"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_tank_threshold_revisions_tank_parameter_effective",
        table_name="tank_threshold_revisions",
    )
    op.drop_table("tank_threshold_revisions")
    op.drop_table("tank_threshold_overrides")

"""Add public tank presentation fields.

Revision ID: 0003_public_tank_experience
Revises: 0002_web_dashboard
"""

from alembic import op
import sqlalchemy as sa


revision = "0003_public_tank_experience"
down_revision = "0002_web_dashboard"
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table("tanks") as batch:
        batch.add_column(sa.Column("tank_code", sa.String(32), nullable=True))
        batch.add_column(sa.Column("habitat_label", sa.String(80), nullable=True))
        batch.add_column(sa.Column("water_type", sa.String(20), nullable=True))
        batch.add_column(sa.Column("volume_liters", sa.Integer(), nullable=True))
        batch.add_column(sa.Column("established_on", sa.Date(), nullable=True))
        batch.add_column(sa.Column("hero_image_url", sa.String(500), nullable=True))
    op.create_index("ix_tanks_tank_code", "tanks", ["tank_code"], unique=True)


def downgrade():
    op.drop_index("ix_tanks_tank_code", table_name="tanks")
    with op.batch_alter_table("tanks") as batch:
        batch.drop_column("hero_image_url")
        batch.drop_column("established_on")
        batch.drop_column("volume_liters")
        batch.drop_column("water_type")
        batch.drop_column("habitat_label")
        batch.drop_column("tank_code")

"""Track whether alerts were resolved by an operator or the monitoring engine.

Revision ID: 0010_alert_resolution_source
Revises: 0009_domain_foundation
"""

from alembic import op
import sqlalchemy as sa


revision = "0010_alert_resolution_source"
down_revision = "0009_domain_foundation"
branch_labels = None
depends_on = None


def upgrade() -> None:
    connection = op.get_bind()
    columns = {column["name"] for column in sa.inspect(connection).get_columns("alerts")}
    if "resolution_source" not in columns:
        op.add_column("alerts", sa.Column("resolution_source", sa.String(length=16), nullable=True))
    op.execute(
        sa.text(
            "UPDATE alerts SET resolution_source = 'operator' "
            "WHERE is_resolved = 1 AND resolved_by_user_id IS NOT NULL "
            "AND resolution_source IS NULL"
        )
    )


def downgrade() -> None:
    connection = op.get_bind()
    columns = {column["name"] for column in sa.inspect(connection).get_columns("alerts")}
    if "resolution_source" in columns:
        with op.batch_alter_table("alerts", recreate="always") as batch:
            batch.drop_column("resolution_source")

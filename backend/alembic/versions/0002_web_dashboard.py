"""Add web dashboard entities and operational fields.

Revision ID: 0002_web_dashboard
Revises: 0001_initial
"""
from alembic import op
import sqlalchemy as sa
import uuid

revision = "0002_web_dashboard"
down_revision = "0001_initial"
branch_labels = None
depends_on = None

def upgrade():
    op.create_table("customers", sa.Column("id", sa.Integer(), primary_key=True), sa.Column("name", sa.String(150), nullable=False), sa.Column("email", sa.String(255)), sa.Column("phone", sa.String(80)), sa.Column("notes", sa.Text()), sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()), sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False), sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False))
    op.create_index("ix_customers_id", "customers", ["id"])
    with op.batch_alter_table("tanks") as batch:
        batch.add_column(sa.Column("public_id", sa.String(36), nullable=True))
        batch.add_column(sa.Column("is_public", sa.Boolean(), nullable=False, server_default=sa.true()))
        batch.add_column(sa.Column("customer_id", sa.Integer(), nullable=True))
        batch.add_column(sa.Column("feeding_schedule", sa.Text(), nullable=True))
        batch.add_column(sa.Column("public_care_notes", sa.Text(), nullable=True))
        batch.create_foreign_key("fk_tanks_customer", "customers", ["customer_id"], ["id"], ondelete="SET NULL")
    op.create_index("ix_tanks_public_id", "tanks", ["public_id"], unique=True)
    op.create_index("ix_tanks_customer_id", "tanks", ["customer_id"])
    # Backfill through SQLAlchemy rather than SQLite-only functions so the same
    # migration works on the production PostgreSQL database.
    connection = op.get_bind()
    tank_ids = connection.execute(sa.text("SELECT id FROM tanks WHERE public_id IS NULL")).scalars()
    for tank_id in tank_ids:
        connection.execute(
            sa.text("UPDATE tanks SET public_id = :public_id WHERE id = :id"),
            {"public_id": str(uuid.uuid4()), "id": tank_id},
        )
    with op.batch_alter_table("tanks") as batch:
        batch.alter_column("public_id", existing_type=sa.String(36), nullable=False)
    with op.batch_alter_table("users") as batch:
        batch.add_column(sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()))
        batch.add_column(sa.Column("must_change_password", sa.Boolean(), nullable=False, server_default=sa.false()))
    with op.batch_alter_table("alerts") as batch:
        batch.add_column(sa.Column("resolved_at", sa.DateTime(timezone=True), nullable=True))
        batch.add_column(sa.Column("resolved_by_user_id", sa.Integer(), nullable=True))
        batch.create_foreign_key("fk_alerts_resolved_by_user", "users", ["resolved_by_user_id"], ["id"], ondelete="SET NULL")
    op.create_table("threshold_configs", sa.Column("id", sa.Integer(), primary_key=True), sa.Column("parameter", sa.String(50), nullable=False, unique=True), sa.Column("unit", sa.String(30), nullable=False), sa.Column("warning_min", sa.Float()), sa.Column("warning_max", sa.Float()), sa.Column("critical_min", sa.Float()), sa.Column("critical_max", sa.Float()), sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.true()), sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False))
    op.create_index("ix_threshold_configs_parameter", "threshold_configs", ["parameter"])
    threshold_configs = sa.table(
        "threshold_configs",
        sa.column("parameter", sa.String), sa.column("unit", sa.String),
        sa.column("warning_min", sa.Float), sa.column("warning_max", sa.Float),
        sa.column("critical_min", sa.Float), sa.column("critical_max", sa.Float),
        sa.column("enabled", sa.Boolean),
    )
    op.bulk_insert(threshold_configs, [
        {"parameter": "temperature", "unit": "°C", "warning_min": 20, "warning_max": 28, "critical_min": 18, "critical_max": 30, "enabled": True},
        {"parameter": "ph", "unit": "pH", "warning_min": 6.5, "warning_max": 7.8, "critical_min": 6, "critical_max": 8.5, "enabled": True},
        {"parameter": "turbidity", "unit": "NTU", "warning_min": None, "warning_max": 8, "critical_min": None, "critical_max": 15, "enabled": True},
        {"parameter": "dissolved_oxygen", "unit": "mg/L", "warning_min": 5, "warning_max": None, "critical_min": 3, "critical_max": None, "enabled": True},
        {"parameter": "tds", "unit": "ppm", "warning_min": 50, "warning_max": 400, "critical_min": 20, "critical_max": 550, "enabled": True},
        {"parameter": "ammonia", "unit": "ppm", "warning_min": None, "warning_max": 0.25, "critical_min": None, "critical_max": 0.5, "enabled": True},
    ])

def downgrade():
    op.drop_table("threshold_configs")
    with op.batch_alter_table("alerts") as b: b.drop_column("resolved_by_user_id"); b.drop_column("resolved_at")
    with op.batch_alter_table("users") as b: b.drop_column("must_change_password"); b.drop_column("is_active")
    op.drop_index("ix_tanks_customer_id", table_name="tanks"); op.drop_index("ix_tanks_public_id", table_name="tanks")
    with op.batch_alter_table("tanks") as b: b.drop_column("public_care_notes"); b.drop_column("feeding_schedule"); b.drop_column("customer_id"); b.drop_column("is_public"); b.drop_column("public_id")
    op.drop_table("customers")

"""Add the one-way retired tank lifecycle and monitoring expectation boundary.

Revision ID: 0012_retired_tank_lifecycle
Revises: 0011_actuator_uncertain_outcomes
"""

from alembic import op
import sqlalchemy as sa


revision = "0012_retired_tank_lifecycle"
down_revision = "0011_actuator_uncertain_outcomes"
branch_labels = None
depends_on = None


def upgrade() -> None:
    connection = op.get_bind()
    is_sqlite = connection.dialect.name == "sqlite"
    inspector = sa.inspect(connection)
    columns = {column["name"] for column in inspector.get_columns("tanks")}
    additions = (
        ("retired_at", sa.DateTime(timezone=True)),
        ("retired_by_user_id", sa.Integer()),
        ("retirement_note", sa.String(length=500)),
        ("monitoring_expected_at", sa.DateTime(timezone=True)),
    )
    missing = [(name, column_type) for name, column_type in additions if name not in columns]
    if is_sqlite and missing:
        with op.batch_alter_table("tanks", recreate="always") as batch:
            for name, column_type in missing:
                batch.add_column(sa.Column(name, column_type, nullable=True))
            if "retired_by_user_id" not in columns:
                batch.create_foreign_key(
                    "fk_tanks_retired_by_user_id_users",
                    "users",
                    ["retired_by_user_id"],
                    ["id"],
                    ondelete="SET NULL",
                )
    elif not is_sqlite:
        for name, column_type in missing:
            op.add_column("tanks", sa.Column(name, column_type, nullable=True))
        if "retired_by_user_id" not in columns:
            op.create_foreign_key(
                "fk_tanks_retired_by_user_id_users",
                "tanks",
                "users",
                ["retired_by_user_id"],
                ["id"],
                ondelete="SET NULL",
            )

    indexes = {index["name"] for index in sa.inspect(connection).get_indexes("tanks")}
    if "ix_tanks_retired_at" not in indexes:
        op.create_index("ix_tanks_retired_at", "tanks", ["retired_at"])
    if "ix_tanks_retired_by_user_id" not in indexes:
        op.create_index("ix_tanks_retired_by_user_id", "tanks", ["retired_by_user_id"])
    if "ix_tanks_monitoring_expected_at" not in indexes:
        op.create_index("ix_tanks_monitoring_expected_at", "tanks", ["monitoring_expected_at"])

    # Existing rows are active. A tank that already has active bridge devices
    # starts a fresh explicit expectation window at migration time; this avoids
    # making the future packet-09 detector treat old device registration dates
    # as a newly missed outage.
    op.execute(
        sa.text(
            "UPDATE tanks SET monitoring_expected_at = CURRENT_TIMESTAMP "
            "WHERE retired_at IS NULL AND EXISTS ("
            "SELECT 1 FROM registered_devices "
            "WHERE registered_devices.tank_id = tanks.id "
            "AND registered_devices.is_active IS TRUE)"
        )
    )


def downgrade() -> None:
    connection = op.get_bind()
    is_sqlite = connection.dialect.name == "sqlite"
    indexes = {index["name"] for index in sa.inspect(connection).get_indexes("tanks")}
    for name in (
        "ix_tanks_monitoring_expected_at",
        "ix_tanks_retired_by_user_id",
        "ix_tanks_retired_at",
    ):
        if name in indexes:
            op.drop_index(name, table_name="tanks")
    if is_sqlite:
        with op.batch_alter_table("tanks", recreate="always") as batch:
            batch.drop_column("monitoring_expected_at")
            batch.drop_column("retirement_note")
            batch.drop_column("retired_by_user_id")
            batch.drop_column("retired_at")
    else:
        foreign_keys = {foreign_key.get("name") for foreign_key in sa.inspect(connection).get_foreign_keys("tanks")}
        if "fk_tanks_retired_by_user_id_users" in foreign_keys:
            op.drop_constraint(
                "fk_tanks_retired_by_user_id_users",
                "tanks",
                type_="foreignkey",
            )
        for column_name in (
            "monitoring_expected_at",
            "retirement_note",
            "retired_by_user_id",
            "retired_at",
        ):
            op.drop_column("tanks", column_name)

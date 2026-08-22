"""Persist uncertain actuator outcomes and physical verification metadata.

Revision ID: 0011_actuator_uncertain_outcomes
Revises: 0010_alert_resolution_source
"""

from datetime import timedelta

from alembic import op
import sqlalchemy as sa


revision = "0011_actuator_uncertain_outcomes"
down_revision = "0010_alert_resolution_source"
branch_labels = None
depends_on = None


def _aware(value):
    return value


def upgrade() -> None:
    connection = op.get_bind()
    inspector = sa.inspect(connection)
    columns = {column["name"] for column in inspector.get_columns("actuator_commands")}
    additions = (
        ("confirmation_deadline_at", sa.DateTime(timezone=True)),
        ("outcome_unknown_at", sa.DateTime(timezone=True)),
        ("physical_verification_user_id", sa.Integer()),
        ("physical_verification_at", sa.DateTime(timezone=True)),
        ("physical_verification_note", sa.String(length=500)),
        ("late_report_fingerprints_json", sa.Text()),
    )
    for name, column_type in additions:
        if name not in columns:
            op.add_column("actuator_commands", sa.Column(name, column_type, nullable=True))

    foreign_keys = sa.inspect(connection).get_foreign_keys("actuator_commands")
    has_verification_foreign_key = any(
        set(foreign_key.get("constrained_columns", [])) == {"physical_verification_user_id"}
        and foreign_key.get("referred_table") == "users"
        for foreign_key in foreign_keys
    )
    if not has_verification_foreign_key:
        if connection.dialect.name == "sqlite":
            with op.batch_alter_table("actuator_commands", recreate="always") as batch_op:
                batch_op.create_foreign_key(
                    "fk_actuator_commands_physical_verification_user_id_users",
                    "users",
                    ["physical_verification_user_id"],
                    ["id"],
                    ondelete="SET NULL",
                )
        else:
            op.create_foreign_key(
                "fk_actuator_commands_physical_verification_user_id_users",
                "actuator_commands",
                "users",
                ["physical_verification_user_id"],
                ["id"],
                ondelete="SET NULL",
            )

    existing_indexes = {index["name"] for index in inspector.get_indexes("actuator_commands")}
    if "ix_actuator_commands_confirmation_deadline_at" not in existing_indexes:
        op.create_index(
            "ix_actuator_commands_confirmation_deadline_at",
            "actuator_commands",
            ["confirmation_deadline_at"],
        )
    if "ix_actuator_commands_physical_verification_user_id" not in existing_indexes:
        op.create_index(
            "ix_actuator_commands_physical_verification_user_id",
            "actuator_commands",
            ["physical_verification_user_id"],
        )

    # Existing executing rows are the only rows that need a confirmation
    # deadline. Queued rows remain governed solely by their queue expiry and get
    # a deadline when they are atomically claimed by the current application.
    command_table = sa.table(
        "actuator_commands",
        sa.column("command_id", sa.String(length=64)),
        sa.column("status", sa.String(length=16)),
        sa.column("executing_at", sa.DateTime(timezone=True)),
        sa.column("confirmation_deadline_at", sa.DateTime(timezone=True)),
    )
    rows = connection.execute(
        sa.select(command_table.c.command_id, command_table.c.executing_at).where(
            command_table.c.status == "executing",
            command_table.c.executing_at.is_not(None),
            command_table.c.confirmation_deadline_at.is_(None),
        )
    ).all()
    for command_id, executing_at in rows:
        connection.execute(
            sa.update(command_table)
            .where(command_table.c.command_id == command_id)
            .values(confirmation_deadline_at=_aware(executing_at) + timedelta(seconds=180))
        )


def downgrade() -> None:
    op.drop_index("ix_actuator_commands_physical_verification_user_id", table_name="actuator_commands")
    op.drop_index("ix_actuator_commands_confirmation_deadline_at", table_name="actuator_commands")
    with op.batch_alter_table("actuator_commands") as batch_op:
        batch_op.drop_column("late_report_fingerprints_json")
        batch_op.drop_column("physical_verification_note")
        batch_op.drop_column("physical_verification_at")
        batch_op.drop_column("physical_verification_user_id")
        batch_op.drop_column("outcome_unknown_at")
        batch_op.drop_column("confirmation_deadline_at")

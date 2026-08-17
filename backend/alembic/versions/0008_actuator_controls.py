"""Add admin actuator commands and bridge-reported actuator state.

Revision ID: 0008_actuator_controls
Revises: 0007_esp32_bridge_devices
"""

from alembic import op
import sqlalchemy as sa


revision = "0008_actuator_controls"
down_revision = "0007_esp32_bridge_devices"
branch_labels = None
depends_on = None


def upgrade() -> None:
    connection = op.get_bind()
    tables = set(sa.inspect(connection).get_table_names())

    if "actuator_commands" not in tables:
        op.create_table(
            "actuator_commands",
            sa.Column("command_id", sa.String(length=64), primary_key=True),
            sa.Column("device_id", sa.String(length=64), sa.ForeignKey("registered_devices.id", ondelete="CASCADE"), nullable=False),
            sa.Column("tank_id", sa.Integer(), sa.ForeignKey("tanks.id", ondelete="CASCADE"), nullable=False),
            sa.Column("actor_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
            sa.Column("actuator", sa.String(length=16), nullable=False),
            sa.Column("action", sa.String(length=24), nullable=False),
            sa.Column("payload_json", sa.Text(), nullable=False),
            sa.Column("status", sa.String(length=16), nullable=False),
            sa.Column("requested_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("executing_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("execution_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("result_json", sa.Text(), nullable=True),
            sa.Column("error_message", sa.String(length=500), nullable=True),
        )
        op.create_index("ix_actuator_commands_device_id", "actuator_commands", ["device_id"])
        op.create_index("ix_actuator_commands_tank_id", "actuator_commands", ["tank_id"])
        op.create_index("ix_actuator_commands_actor_user_id", "actuator_commands", ["actor_user_id"])
        op.create_index("ix_actuator_commands_status", "actuator_commands", ["status"])
        op.create_index("ix_actuator_commands_requested_at", "actuator_commands", ["requested_at"])
        op.create_index("ix_actuator_commands_expires_at", "actuator_commands", ["expires_at"])

    if "actuator_states" not in tables:
        op.create_table(
            "actuator_states",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("device_id", sa.String(length=64), sa.ForeignKey("registered_devices.id", ondelete="CASCADE"), nullable=False),
            sa.Column("tank_id", sa.Integer(), sa.ForeignKey("tanks.id", ondelete="CASCADE"), nullable=False),
            sa.Column("actuator", sa.String(length=16), nullable=False),
            sa.Column("state_json", sa.Text(), nullable=False),
            sa.Column("refreshed_at", sa.DateTime(timezone=True), nullable=False),
            sa.UniqueConstraint("device_id", "actuator", name="uq_actuator_states_device_actuator"),
        )
        op.create_index("ix_actuator_states_device_id", "actuator_states", ["device_id"])
        op.create_index("ix_actuator_states_tank_id", "actuator_states", ["tank_id"])
        op.create_index("ix_actuator_states_refreshed_at", "actuator_states", ["refreshed_at"])

    if "actuator_state_history" not in tables:
        op.create_table(
            "actuator_state_history",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("device_id", sa.String(length=64), sa.ForeignKey("registered_devices.id", ondelete="CASCADE"), nullable=False),
            sa.Column("tank_id", sa.Integer(), sa.ForeignKey("tanks.id", ondelete="CASCADE"), nullable=False),
            sa.Column("actuator", sa.String(length=16), nullable=False),
            sa.Column("command_id", sa.String(length=64), sa.ForeignKey("actuator_commands.command_id", ondelete="SET NULL"), nullable=True),
            sa.Column("state_json", sa.Text(), nullable=False),
            sa.Column("reported_at", sa.DateTime(timezone=True), nullable=False),
        )
        op.create_index("ix_actuator_state_history_device_id", "actuator_state_history", ["device_id"])
        op.create_index("ix_actuator_state_history_tank_id", "actuator_state_history", ["tank_id"])
        op.create_index("ix_actuator_state_history_actuator", "actuator_state_history", ["actuator"])
        op.create_index("ix_actuator_state_history_reported_at", "actuator_state_history", ["reported_at"])


def downgrade() -> None:
    op.drop_index("ix_actuator_state_history_reported_at", table_name="actuator_state_history")
    op.drop_index("ix_actuator_state_history_actuator", table_name="actuator_state_history")
    op.drop_index("ix_actuator_state_history_tank_id", table_name="actuator_state_history")
    op.drop_index("ix_actuator_state_history_device_id", table_name="actuator_state_history")
    op.drop_table("actuator_state_history")

    op.drop_index("ix_actuator_states_refreshed_at", table_name="actuator_states")
    op.drop_index("ix_actuator_states_tank_id", table_name="actuator_states")
    op.drop_index("ix_actuator_states_device_id", table_name="actuator_states")
    op.drop_table("actuator_states")

    op.drop_index("ix_actuator_commands_expires_at", table_name="actuator_commands")
    op.drop_index("ix_actuator_commands_requested_at", table_name="actuator_commands")
    op.drop_index("ix_actuator_commands_status", table_name="actuator_commands")
    op.drop_index("ix_actuator_commands_actor_user_id", table_name="actuator_commands")
    op.drop_index("ix_actuator_commands_tank_id", table_name="actuator_commands")
    op.drop_index("ix_actuator_commands_device_id", table_name="actuator_commands")
    op.drop_table("actuator_commands")

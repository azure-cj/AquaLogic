"""Add revocable authentication, security audit, and public privacy fields.

Revision ID: 0006_auth_security_hardening
Revises: 0005_analytics_threshold_history
"""

from alembic import op
import sqlalchemy as sa


revision = "0006_auth_security_hardening"
down_revision = "0005_analytics_threshold_history"
branch_labels = None
depends_on = None


def upgrade() -> None:
    connection = op.get_bind()
    inspector = sa.inspect(connection)
    user_columns = {column["name"] for column in inspector.get_columns("users")}
    tank_columns = {column["name"] for column in inspector.get_columns("tanks")}
    if "token_version" not in user_columns or "password_changed_at" not in user_columns:
        with op.batch_alter_table("users") as batch:
            if "token_version" not in user_columns:
                batch.add_column(sa.Column("token_version", sa.Integer(), nullable=False, server_default="0"))
            if "password_changed_at" not in user_columns:
                batch.add_column(sa.Column("password_changed_at", sa.DateTime(timezone=True), nullable=True))
    if "public_location" not in tank_columns:
        with op.batch_alter_table("tanks") as batch:
            batch.add_column(sa.Column("public_location", sa.String(length=150), nullable=True))

    tables = set(inspector.get_table_names())
    if "auth_sessions" not in tables:
        op.create_table("auth_sessions", sa.Column("id", sa.String(36), primary_key=True), sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False), sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False), sa.Column("revoked_at", sa.DateTime(timezone=True)), sa.Column("revoke_reason", sa.String(80)), sa.Column("client_ip_hash", sa.String(64)), sa.Column("user_agent", sa.String(256)), sa.Column("amr", sa.String(80), nullable=False, server_default="pwd"), sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()), sa.Column("last_seen_at", sa.DateTime(timezone=True)))
    if "refresh_tokens" not in tables:
        op.create_table("refresh_tokens", sa.Column("token_hash", sa.String(64), primary_key=True), sa.Column("session_id", sa.String(36), sa.ForeignKey("auth_sessions.id", ondelete="CASCADE"), nullable=False), sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False), sa.Column("consumed_at", sa.DateTime(timezone=True)), sa.Column("replaced_by_hash", sa.String(64)), sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()))
    if "account_setup_tokens" not in tables:
        op.create_table("account_setup_tokens", sa.Column("token_hash", sa.String(64), primary_key=True), sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False), sa.Column("purpose", sa.String(24), nullable=False), sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False), sa.Column("consumed_at", sa.DateTime(timezone=True)), sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()))
    if "auth_throttles" not in tables:
        op.create_table("auth_throttles", sa.Column("id", sa.Integer(), primary_key=True), sa.Column("scope", sa.String(16), nullable=False), sa.Column("key_hash", sa.String(64), nullable=False), sa.Column("failures", sa.Integer(), nullable=False, server_default="0"), sa.Column("window_started_at", sa.DateTime(timezone=True), nullable=False), sa.Column("blocked_until", sa.DateTime(timezone=True)), sa.UniqueConstraint("scope", "key_hash", name="uq_auth_throttles_scope_key"))
    if "security_audit_events" not in tables:
        op.create_table("security_audit_events", sa.Column("id", sa.Integer(), primary_key=True), sa.Column("event_type", sa.String(80), nullable=False), sa.Column("outcome", sa.String(32), nullable=False), sa.Column("request_id", sa.String(64)), sa.Column("actor_user_id", sa.Integer()), sa.Column("target_type", sa.String(80)), sa.Column("target_id", sa.String(80)), sa.Column("client_ip_hash", sa.String(64)), sa.Column("user_agent", sa.String(256)), sa.Column("details", sa.Text()), sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()))

    def ensure_index(name: str, table: str, columns: list[str]) -> None:
        if name not in {item["name"] for item in sa.inspect(connection).get_indexes(table)}:
            op.create_index(name, table, columns)

    ensure_index("ix_auth_sessions_user_id", "auth_sessions", ["user_id"])
    ensure_index("ix_auth_sessions_expires_at", "auth_sessions", ["expires_at"])
    ensure_index("ix_refresh_tokens_session_id", "refresh_tokens", ["session_id"])
    ensure_index("ix_refresh_tokens_expires_at", "refresh_tokens", ["expires_at"])
    ensure_index("ix_account_setup_tokens_user_id", "account_setup_tokens", ["user_id"])
    ensure_index("ix_account_setup_tokens_expires_at", "account_setup_tokens", ["expires_at"])
    ensure_index("ix_auth_throttles_key_hash", "auth_throttles", ["key_hash"])
    ensure_index("ix_security_audit_events_created_at", "security_audit_events", ["created_at"])
    ensure_index("ix_security_audit_events_event_type", "security_audit_events", ["event_type"])
    ensure_index("ix_security_audit_events_request_id", "security_audit_events", ["request_id"])
    ensure_index("ix_security_audit_events_actor_user_id", "security_audit_events", ["actor_user_id"])


def downgrade() -> None:
    connection = op.get_bind()
    tables = set(sa.inspect(connection).get_table_names())
    for table in ("security_audit_events", "auth_throttles", "account_setup_tokens", "refresh_tokens", "auth_sessions"):
        if table in tables:
            op.drop_table(table)
    with op.batch_alter_table("tanks") as batch:
        batch.drop_column("public_location")
    with op.batch_alter_table("users") as batch:
        batch.drop_column("password_changed_at")
        batch.drop_column("token_version")

"""Add server-side sessions table (TMB)

Revision ID: 0002
Revises: 0001
Create Date: 2025-01-01 00:00:01.000000
"""
from alembic import op
import sqlalchemy as sa
import sqlmodel

revision = '0002'
down_revision = '0001'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'sessions',
        sa.Column('id', sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column('cognito_sub', sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column('refresh_token', sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('expires_at', sa.DateTime(), nullable=False),
        sa.Column('rotated_at', sa.DateTime(), nullable=True),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_sessions_cognito_sub'), 'sessions', ['cognito_sub'], unique=False)
    op.create_index(op.f('ix_sessions_expires_at'), 'sessions', ['expires_at'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_sessions_expires_at'), table_name='sessions')
    op.drop_index(op.f('ix_sessions_cognito_sub'), table_name='sessions')
    op.drop_table('sessions')

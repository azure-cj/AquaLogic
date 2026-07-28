"""Add fish species directory fields.

Revision ID: 0004_fish_species_directory
Revises: 0003_public_tank_experience
"""

from alembic import op
import sqlalchemy as sa


revision = "0004_fish_species_directory"
down_revision = "0003_public_tank_experience"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("fish_species") as batch:
        batch.add_column(
            sa.Column(
                "category",
                sa.String(length=80),
                nullable=False,
                server_default="Other",
            )
        )
        batch.add_column(sa.Column("diet_type", sa.String(length=20), nullable=True))

    connection = op.get_bind()
    connection.execute(
        sa.text(
            """
            UPDATE fish_species
            SET category = CASE
                WHEN common_name IN ('Guppy', 'Molly', 'Platy', 'Swordtail') THEN 'Livebearers'
                WHEN common_name IN ('Angelfish', 'Discus', 'Oscar') THEN 'Cichlids'
                WHEN common_name IN ('Goldfish', 'Koi') THEN 'Coldwater'
                WHEN common_name IN ('Neon Tetra', 'Zebra Danio', 'Cherry Barb') THEN 'Schooling fish'
                WHEN common_name = 'Corydoras Catfish' THEN 'Bottom dwellers'
                WHEN common_name = 'Clownfish' THEN 'Marine'
                WHEN common_name = 'Betta' THEN 'Labyrinth fish'
                ELSE 'Other'
            END
            """
        )
    )
    connection.execute(
        sa.text(
            """
            UPDATE fish_species
            SET diet_type = CASE
                WHEN lower(coalesce(diet, '')) LIKE '%carnivor%' THEN 'Carnivore'
                WHEN lower(coalesce(diet, '')) LIKE '%herbivor%' THEN 'Herbivore'
                WHEN diet IS NOT NULL AND diet <> '' THEN 'Omnivore'
                ELSE NULL
            END
            """
        )
    )


def downgrade() -> None:
    with op.batch_alter_table("fish_species") as batch:
        batch.drop_column("diet_type")
        batch.drop_column("category")

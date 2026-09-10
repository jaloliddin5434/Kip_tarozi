"""kip togrilash zayavkalari

Operator "Smena tarixi" ro'yxatidagi bir kip uchun mahsulot/partiya
noto'g'ri tanlanganini bildirib, admin tasdiqlashini so'raydigan zayavka
(kamera_tasdiq_sorovlari bilan bir xil tasdiqlash/rad-etish naqshi).

Revision ID: fe1be70c1f3d
Revises: 7c2f1a9b4d10
Create Date: 2026-09-10 11:40:49.681757

"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "fe1be70c1f3d"
down_revision: str | None = "7c2f1a9b4d10"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None

# create_type=False — CREATE TYPE'ni quyida o'zimiz (idempotent) boshqaramiz
# (7c2f1a9b4d10 bilan bir xil naqsh).
_holati_turi = postgresql.ENUM(
    "kutilmoqda", "tasdiqlangan", "rad_etilgan", name="kip_togrilash_holati_turi", create_type=False
)


def upgrade() -> None:
    op.execute(
        """
        DO $$ BEGIN
            CREATE TYPE kip_togrilash_holati_turi AS ENUM ('kutilmoqda', 'tasdiqlangan', 'rad_etilgan');
        EXCEPTION WHEN duplicate_object THEN NULL;
        END $$;
        """
    )
    op.create_table(
        "kip_togrilash_zayavkalari",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("kip_id", sa.Integer(), nullable=False),
        sa.Column("operator_id", sa.Integer(), nullable=False),
        sa.Column("eski_mahsulot_id", sa.Integer(), nullable=False),
        sa.Column("eski_partiya_id", sa.Integer(), nullable=False),
        sa.Column("yangi_mahsulot_id", sa.Integer(), nullable=False),
        sa.Column("yangi_partiya_id", sa.Integer(), nullable=False),
        sa.Column("sabab", sa.Text(), nullable=False),
        sa.Column("vaqt", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("holati", _holati_turi, server_default="kutilmoqda", nullable=False),
        sa.Column("hal_qilgan_id", sa.Integer(), nullable=True),
        sa.Column("hal_qilingan_vaqt", sa.DateTime(timezone=True), nullable=True),
        sa.Column("hal_qilish_manbasi", sa.String(length=50), nullable=True),
        sa.Column("izoh", sa.Text(), nullable=True),
        sa.ForeignKeyConstraint(["kip_id"], ["kiplar.id"]),
        sa.ForeignKeyConstraint(["operator_id"], ["foydalanuvchilar.id"]),
        sa.ForeignKeyConstraint(["eski_mahsulot_id"], ["mahsulotlar.id"]),
        sa.ForeignKeyConstraint(["eski_partiya_id"], ["partiyalar.id"]),
        sa.ForeignKeyConstraint(["yangi_mahsulot_id"], ["mahsulotlar.id"]),
        sa.ForeignKeyConstraint(["yangi_partiya_id"], ["partiyalar.id"]),
        sa.ForeignKeyConstraint(["hal_qilgan_id"], ["foydalanuvchilar.id"]),
        sa.PrimaryKeyConstraint("id"),
    )


def downgrade() -> None:
    op.drop_table("kip_togrilash_zayavkalari")
    op.execute("DROP TYPE IF EXISTS kip_togrilash_holati_turi")

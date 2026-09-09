"""kamera tasdiq sorovlari

Kamera sozlangan-u surat ololmasa kip saqlanmaydi — o'rniga shu jadvalga
"kutilayotgan tasdiq" yoziladi, Admin tasdiqlagach kip suratsiz saqlanadi.

Revision ID: 7c2f1a9b4d10
Revises: d982006fe43f
Create Date: 2026-09-09 11:00:00.000000

"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "7c2f1a9b4d10"
down_revision: str | None = "d982006fe43f"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None

# create_type=False — CREATE TYPE'ni quyida o'zimiz (idempotent) boshqaramiz;
# smena_turi allaqachon mavjud, kamera_tasdiq_holati_turi esa DO-blok bilan
# faqat yo'q bo'lsa yaratiladi (downgrade -> re-upgrade ham xatosiz ishlasin).
_smena_turi = postgresql.ENUM("A", "B", "C", "D", name="smena_turi", create_type=False)
_holati_turi = postgresql.ENUM(
    "kutilmoqda", "tasdiqlangan", "rad_etilgan", name="kamera_tasdiq_holati_turi", create_type=False
)


def upgrade() -> None:
    op.execute(
        """
        DO $$ BEGIN
            CREATE TYPE kamera_tasdiq_holati_turi AS ENUM ('kutilmoqda', 'tasdiqlangan', 'rad_etilgan');
        EXCEPTION WHEN duplicate_object THEN NULL;
        END $$;
        """
    )
    op.create_table(
        "kamera_tasdiq_sorovlari",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("mijoz_id", sa.String(length=36), nullable=False),
        sa.Column("partiya_id", sa.Integer(), nullable=False),
        sa.Column("ogirlik", sa.Numeric(precision=6, scale=2), nullable=False),
        sa.Column("smena", _smena_turi, nullable=False),
        sa.Column("operator_id", sa.Integer(), nullable=False),
        sa.Column("stansiya_id", sa.Integer(), nullable=True),
        sa.Column("mahalliy_vaqt", sa.DateTime(timezone=True), nullable=False),
        sa.Column("majburiy", sa.Boolean(), server_default="false", nullable=False),
        sa.Column("vaqt", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("holati", _holati_turi, server_default="kutilmoqda", nullable=False),
        sa.Column("kip_id", sa.Integer(), nullable=True),
        sa.Column("hal_qilgan_id", sa.Integer(), nullable=True),
        sa.Column("hal_qilingan_vaqt", sa.DateTime(timezone=True), nullable=True),
        sa.Column("hal_qilish_manbasi", sa.String(length=50), nullable=True),
        sa.Column("izoh", sa.Text(), nullable=True),
        sa.ForeignKeyConstraint(["partiya_id"], ["partiyalar.id"]),
        sa.ForeignKeyConstraint(["operator_id"], ["foydalanuvchilar.id"]),
        sa.ForeignKeyConstraint(["stansiya_id"], ["stansiyalar.id"]),
        sa.ForeignKeyConstraint(["kip_id"], ["kiplar.id"]),
        sa.ForeignKeyConstraint(["hal_qilgan_id"], ["foydalanuvchilar.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("mijoz_id"),
    )


def downgrade() -> None:
    op.drop_table("kamera_tasdiq_sorovlari")
    op.execute("DROP TYPE IF EXISTS kamera_tasdiq_holati_turi")

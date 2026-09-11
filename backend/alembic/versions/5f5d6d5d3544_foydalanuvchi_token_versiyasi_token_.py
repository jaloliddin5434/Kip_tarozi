"""foydalanuvchi token versiyasi (token bekor qilish mexanizmi)

AUDIT TOPILMASI (tuzatilmoqda): JWT token ~10 yil yashaydi
(ACCESS_TOKEN_EXPIRE_MINUTES) va uni bekor qilishning HECH QANDAY yo'li
yo'q edi — token o'g'irlansa yoki foydalanuvchi parolini o'zgartirsa ham,
eski token cheksiz ishlashda davom etardi.

Bu migratsiya `foydalanuvchilar.token_versiyasi` ustunini qo'shadi (standart
1). Endi:
- login paytida yaratilgan JWT ichiga o'sha paytdagi qiymat "tv" claim
  sifatida yoziladi;
- `joriy_foydalanuvchi()` har so'rovda tokendagi "tv"ni bazadagi joriy
  qiymat bilan solishtiradi — mos kelmasa 401;
- parol o'zgartirilganda (`PATCH /foydalanuvchilar/{id}`) yoki admin
  "Tokenlarni bekor qilish" amalini bajarganda (`POST
  /foydalanuvchilar/{id}/tokenlarni-bekor-qilish`) `token_versiyasi +1`
  oshiriladi — shu hisobning BARCHA eski tokenlari darhol ishlamay qoladi.

Token MUDDATI (ACCESS_TOKEN_EXPIRE_MINUTES) bu migratsiyada QISQARTIRILMAYDI
— bu alohida, kelajakdagi vazifa (offline navbat rezilientligi bilan
bog'liq, refresh-token arxitekturasi talab qilishi mumkin).

MUHIM: mavjud (bu migratsiyadan OLDIN chiqarilgan) tokenlarda "tv" claim'i
umuman yo'q — `joriy_foydalanuvchi()` bunday holatni ham "mos kelmadi" deb
hisoblaydi (xavfsiz standart: noaniqlikda rad etish). Amaliy natija: bu
migratsiya qo'llanganidan keyin barcha FOYDALANUVCHILAR BIR MARTA qayta
login qilishi kerak bo'ladi (login o'zi oddiy va tez, bir martalik holat).

Revision ID: 5f5d6d5d3544
Revises: 68a051b132ed
Create Date: 2026-09-12 00:00:00.000000

"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = '5f5d6d5d3544'
down_revision: str | None = '68a051b132ed'
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "foydalanuvchilar",
        sa.Column("token_versiyasi", sa.Integer(), server_default="1", nullable=False),
    )


def downgrade() -> None:
    op.drop_column("foydalanuvchilar", "token_versiyasi")

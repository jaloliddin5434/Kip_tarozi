"""kiplar va boshqa jadvallarga performance indekslari

AUDIT TOPILMASI (tuzatilmoqda): boshlang'ich migratsiyadan beri bazada
birorta ham ikkilamchi indeks yo'q edi (faqat `ix_foydalanuvchilar_login`
va unique constraint'lar). PostgreSQL FOREIGN KEY ustunlariga AVTOMATIK
indeks yaratmaydi — hozircha (kichik hajmda) sezilmasa ham, mavsum
davomida yoki operator/kip soni ko'paysa Dashboard/Statistika/Hujjatlar/
Partiyalar ekranlarining har biri to'liq jadval skani qiladi.

Bu migratsiya QUYIDAGILARNI QO'SHADI (faqat indeks — jadval strukturasi,
ustunlar, cheklovlar o'zgarmaydi, mavjud so'rovlar natijasi bir xil qoladi,
faqat tezroq bajariladi):

- `kiplar`: `vaqt`, `smena`, `holati`, `operator_id` (alohida) + ikkita
  composite — `(partiya_id, holati)` (masalan `_javobga_ayirib` jamlanmasi,
  `_dublikat_topish`) va `(vaqt, holati)` (davr+holat bo'yicha filtrlash).
  ESLATMA: `partiya_id` uchun ALOHIDA oddiy indeks QO'SHILMADI — u allaqachon
  ham `uq_kip_partiya_raqam` (partiya_id, kip_raqami) unique cheklovining
  boshlang'ich ustuni orqali, ham yangi `(partiya_id, holati)` composite
  orqali qamrab olingan (uchinchi, ortiqcha indeks yozish tezligini
  bekorga sekinlashtirardi).
- `partiyalar`: `holati`, `sotuv_sanasi` (moliyaviy hisobot shu ikkalasini
  birga filtrlaydi — Postgres ikkala oddiy indeksni bitmap AND orqali
  birlashtira oladi). `mahsulot_id` uchun alohida indeks qo'shilmadi — u
  `uq_partiya_mahsulot_raqam` (mahsulot_id, partiya_raqami) orqali allaqachon
  qamrab olingan.
- `audit_log`: composite `(jadval_nomi, yozuv_id)` — kip/foydalanuvchi
  tafsiloti ochilganda audit tarixini qidirish uchun.
- `kamera_tasdiq_sorovlari`: composite `(operator_id, holati, vaqt)` —
  `GET /kamera-tasdiq/mening-kutilayotganim` operator tomonidan har necha
  soniyada pollanadi.
- `kip_togrilash_zayavkalari`: composite `(operator_id, holati, vaqt)` —
  xuddi shu naqsh (kamera_tasdiq bilan bir xil oqim).
- `shubhali_holatlar`: composite `(smena, holati, operator_id, vaqt)` —
  `_bloklovchi_hodisa`/`bloklovchini_tekshir` operator tomonidan har 5
  soniyada pollanadigan ENG TEZ-TEZ ishlaydigan so'rov (`WHERE smena=? AND
  holati='yangi' ORDER BY vaqt DESC LIMIT 1`).

ALOHIDA MUAMMO (audit topilmasi) — `func.date(Kip.vaqt)` FUNKSIONAL
INDEKSI QO'SHILMADI, chunki BU AMALDA IMKONSIZ: loyihada deyarli barcha
davr-filtrlar `func.date(Kip.vaqt) >= boshlanish AND <= tugash` ko'rinishida
— `date()` funksiyasi ustunga qo'llangani uchun oddiy `vaqt` indeksi bunday
so'rovda ISHLATILMAYDI (sargable emas). `CREATE INDEX ... ON kiplar
(date(vaqt))` sinovdan o'tkazildi va PostgreSQL uni RAD ETDI:
`date(timestamptz)` STABLE (natija sessiya TimeZone sozlamasiga bog'liq),
IMMUTABLE EMAS — Postgres index ifodalarida faqat IMMUTABLE funksiyalarga
ruxsat beradi ("functions in index expression must be marked IMMUTABLE").
O'zi yozilgan IMMUTABLE wrapper funksiya bilan aylanib o'tish MUMKIN, lekin
bu holda ham `func.date(Kip.vaqt)`ning barcha ~15-20 chaqiruv joyi
(dashboard.py, statistika.py, hisobotlar.py, hujjatlar.py, kamera_tasdiq.py,
kip_togrilash.py, shubhali_holatlar.py) shu YANGI funksiyaga
o'tkazilmaguncha indeks HECH QANDAY so'rov tomonidan ishlatilmaydi (befoyda
yotadi) — bu esa ALOHIDA (kattaroq) sargable-refaktoring vazifasining bir
qismi, shuning uchun QILINMAYDI. To'g'ri yechim keyinroq: (a) barcha shunday
joylarni sargable oraliqqa (`Kip.vaqt >= boshlanish_dt AND Kip.vaqt <
tugash_dt + 1 kun`) o'tkazish — shunda yuqoridagi oddiy `ix_kiplar_vaqt`
indeksi to'g'ridan-to'g'ri ishlaydi, qo'shimcha funksional indeks shart
emas.

Revision ID: 68a051b132ed
Revises: ce387d077c86
Create Date: 2026-09-11 09:43:04.494774

"""
from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = '68a051b132ed'
down_revision: str | None = 'ce387d077c86'
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    # --- kiplar ---
    op.create_index("ix_kiplar_vaqt", "kiplar", ["vaqt"])
    op.create_index("ix_kiplar_smena", "kiplar", ["smena"])
    op.create_index("ix_kiplar_holati", "kiplar", ["holati"])
    op.create_index("ix_kiplar_operator_id", "kiplar", ["operator_id"])
    op.create_index("ix_kiplar_partiya_holati", "kiplar", ["partiya_id", "holati"])
    op.create_index("ix_kiplar_vaqt_holati", "kiplar", ["vaqt", "holati"])

    # --- partiyalar ---
    op.create_index("ix_partiyalar_holati", "partiyalar", ["holati"])
    op.create_index("ix_partiyalar_sotuv_sanasi", "partiyalar", ["sotuv_sanasi"])

    # --- audit_log ---
    op.create_index("ix_audit_log_jadval_yozuv", "audit_log", ["jadval_nomi", "yozuv_id"])

    # --- kamera_tasdiq_sorovlari ---
    op.create_index(
        "ix_kamera_tasdiq_operator_holati_vaqt",
        "kamera_tasdiq_sorovlari",
        ["operator_id", "holati", "vaqt"],
    )

    # --- kip_togrilash_zayavkalari ---
    op.create_index(
        "ix_kip_togrilash_operator_holati_vaqt",
        "kip_togrilash_zayavkalari",
        ["operator_id", "holati", "vaqt"],
    )

    # --- shubhali_holatlar ---
    op.create_index(
        "ix_shubhali_holatlar_smena_holati_operator_vaqt",
        "shubhali_holatlar",
        ["smena", "holati", "operator_id", "vaqt"],
    )


def downgrade() -> None:
    op.drop_index("ix_shubhali_holatlar_smena_holati_operator_vaqt", table_name="shubhali_holatlar")
    op.drop_index("ix_kip_togrilash_operator_holati_vaqt", table_name="kip_togrilash_zayavkalari")
    op.drop_index("ix_kamera_tasdiq_operator_holati_vaqt", table_name="kamera_tasdiq_sorovlari")
    op.drop_index("ix_audit_log_jadval_yozuv", table_name="audit_log")
    op.drop_index("ix_partiyalar_sotuv_sanasi", table_name="partiyalar")
    op.drop_index("ix_partiyalar_holati", table_name="partiyalar")
    op.drop_index("ix_kiplar_vaqt_holati", table_name="kiplar")
    op.drop_index("ix_kiplar_partiya_holati", table_name="kiplar")
    op.drop_index("ix_kiplar_operator_id", table_name="kiplar")
    op.drop_index("ix_kiplar_holati", table_name="kiplar")
    op.drop_index("ix_kiplar_smena", table_name="kiplar")
    op.drop_index("ix_kiplar_vaqt", table_name="kiplar")

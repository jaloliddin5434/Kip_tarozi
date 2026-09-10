"""Excel hisobot jadvallarini yasash.

`smena_mahsulot_jadval()` mantig'idan IKKI joy foydalanadi:
- REST endpoint `GET /hisobotlar/smena-mahsulot-excel` (`routes/hisobotlar.py`)
- kunlik zaxira skripti `scripts/backup_tuzilma.py`

Shu tufayli "bitta kun + bitta smena + bitta mahsulot" Excel ko'rinishi
bitta joyda ta'riflanadi.
"""

from datetime import date

from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill
from openpyxl.utils import get_column_letter
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models.foydalanuvchi import Smena
from app.models.kip import HISOBLANADIGAN_HOLATLAR, Kip
from app.models.mahsulot import Mahsulot
from app.models.partiya import Partiya

_JAMI_FON = PatternFill("solid", fgColor="D6E4F0")


def smena_mahsulot_jadval(db: Session, sana: date, smena: Smena, mahsulot: Mahsulot) -> Workbook:
    """Bitta KUN + bitta SMENA + bitta MAHSULOT uchun tor eksport — shu
    kombinatsiyada tortilgan har bir kip alohida qator (kip raqami, partiya,
    vaqt, kg) va oxirida JAMI qatori. Faqat HISOBLANADIGAN holatdagi kiplar
    (bekor qilinganlar chiqarib tashlanadi)."""
    qatorlar = db.execute(
        select(Kip.kip_raqami, Kip.vaqt, Kip.ogirlik, Partiya.partiya_raqami)
        .join(Partiya, Partiya.id == Kip.partiya_id)
        .where(
            Partiya.mahsulot_id == mahsulot.id,
            Kip.holati.in_(HISOBLANADIGAN_HOLATLAR),
            Kip.smena == smena,
            func.date(Kip.vaqt) == sana,
        )
        .order_by(Kip.vaqt, Kip.kip_raqami)
    ).all()

    wb = Workbook()
    ws = wb.active
    ws.title = f"Smena {smena.value} — {mahsulot.nomi}"[:31]

    ws.append([f"Smena {smena.value} — {mahsulot.nomi} — {sana.isoformat()}"])
    ws["A1"].font = Font(bold=True, size=14)
    ws.append([])

    ws.append(["Kip №", "Partiya №", "Vaqt", "Og'irlik, kg"])
    for hujayra in ws[ws.max_row]:
        hujayra.font = Font(bold=True)

    jami_kg = 0.0
    for kip_raqami, vaqt, ogirlik, partiya_raqami in qatorlar:
        ws.append([kip_raqami, partiya_raqami, vaqt.strftime("%H:%M:%S"), round(float(ogirlik), 2)])
        jami_kg += float(ogirlik)

    ws.append([f"JAMI ({len(qatorlar)} kip)", "", "", round(jami_kg, 2)])
    for hujayra in ws[ws.max_row]:
        hujayra.font = Font(bold=True)
        hujayra.fill = _JAMI_FON

    for i, kenglik in enumerate([18, 12, 12, 14], start=1):
        ws.column_dimensions[get_column_letter(i)].width = kenglik

    return wb

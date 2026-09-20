"""Excel hisobot jadvallarini yasash.

`smena_mahsulot_jadval()` mantig'idan UCH joy foydalanadi:
- REST endpoint `GET /hisobotlar/smena-mahsulot-excel` (`routes/hisobotlar.py`)
- REST endpoint `GET /hisobotlar/smena-excel` (`smena_barcha_mahsulotlar_zip()`
  orqali — har mahsulot uchun ALOHIDA fayl, ZIP ichida)
- kunlik zaxira skripti `scripts/backup_tuzilma.py`

Shu tufayli "bitta kun + bitta smena + bitta mahsulot" Excel ko'rinishi
bitta joyda ta'riflanadi.
"""

import zipfile
from datetime import date
from io import BytesIO

from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill
from openpyxl.utils import get_column_letter
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.foydalanuvchi import Smena
from app.models.kip import HISOBLANADIGAN_HOLATLAR, Kip
from app.models.mahsulot import Mahsulot
from app.models.partiya import Partiya
from app.services.davr import sargable_oraliq

_JAMI_FON = PatternFill("solid", fgColor="D6E4F0")

# Dashboard/Statistika/Hujjatlar/Operator ekranlarida ishlatiladigan bilan
# bir xil ko'rinish tartibi (alifbo bo'yicha emas).
_MAHSULOT_TARTIBI = ["tola", "lint", "pux", "ulyuk"]


def smena_mahsulot_jadval(db: Session, sana: date, smena: Smena, mahsulot: Mahsulot) -> Workbook:
    """Bitta KUN + bitta SMENA + bitta MAHSULOT uchun tor eksport — shu
    kombinatsiyada tortilgan har bir kip alohida qator (kip raqami, partiya,
    vaqt, kg) va oxirida JAMI qatori. Faqat HISOBLANADIGAN holatdagi kiplar
    (bekor qilinganlar chiqarib tashlanadi)."""
    pastki, yuqori = sargable_oraliq(sana, sana)
    qatorlar = db.execute(
        select(Kip.kip_raqami, Kip.vaqt, Kip.ogirlik, Partiya.partiya_raqami)
        .join(Partiya, Partiya.id == Kip.partiya_id)
        .where(
            Partiya.mahsulot_id == mahsulot.id,
            Kip.holati.in_(HISOBLANADIGAN_HOLATLAR),
            Kip.smena == smena,
            Kip.vaqt >= pastki,
            Kip.vaqt < yuqori,
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


def smena_barcha_mahsulotlar_zip(db: Session, sana: date, smena: Smena) -> bytes:
    """Bitta KUN + bitta SMENA uchun — o'sha kuni/smenada HAQIQATDA (kamida
    bitta hisoblanadigan kip bilan) ishlatilgan har bir mahsulot uchun
    alohida Excel varag'ini (`smena_mahsulot_jadval()`, xuddi
    `/smena-mahsulot-excel` va kunlik zaxira bilan bir xil) yasab, bitta ZIP
    arxivga joylaydi. Ma'lumoti yo'q mahsulot uchun FAYL YARATILMAYDI (arxivda
    umuman qatnashmaydi). Hech qanday mahsulotda ma'lumot bo'lmasa — bo'sh
    (0 ta yozuvli, lekin baribir ochiladigan) ZIP qaytadi."""
    pastki, yuqori = sargable_oraliq(sana, sana)
    mos_kodlari = set(
        db.execute(
            select(Mahsulot.kod)
            .join(Partiya, Partiya.mahsulot_id == Mahsulot.id)
            .join(Kip, Kip.partiya_id == Partiya.id)
            .where(
                Kip.holati.in_(HISOBLANADIGAN_HOLATLAR),
                Kip.smena == smena,
                Kip.vaqt >= pastki,
                Kip.vaqt < yuqori,
            )
            .distinct()
        )
        .scalars()
        .all()
    )

    buffer = BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        if mos_kodlari:
            mahsulotlar = {
                m.kod: m
                for m in db.execute(select(Mahsulot).where(Mahsulot.kod.in_(mos_kodlari))).scalars()
            }
            for kod in _MAHSULOT_TARTIBI:
                mahsulot = mahsulotlar.get(kod)
                if mahsulot is None:
                    continue
                wb = smena_mahsulot_jadval(db, sana, smena, mahsulot)
                fayl_buffer = BytesIO()
                wb.save(fayl_buffer)
                nom_qismi = mahsulot.nomi.replace(" ", "_") or mahsulot.kod
                zf.writestr(f"Smena_{smena.value}_{nom_qismi}_{sana.isoformat()}.xlsx", fayl_buffer.getvalue())

    buffer.seek(0)
    return buffer.getvalue()

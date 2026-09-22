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
from openpyxl.styles import Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.worksheet import Worksheet
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.foydalanuvchi import Foydalanuvchi, Smena
from app.models.kip import HISOBLANADIGAN_HOLATLAR, Kip
from app.models.mahsulot import Mahsulot
from app.models.partiya import Partiya
from app.services.davr import sargable_oraliq

# Dashboard/Statistika/Hujjatlar/Operator ekranlarida ishlatiladigan bilan
# bir xil ko'rinish tartibi (alifbo bo'yicha emas).
_MAHSULOT_TARTIBI = ["tola", "lint", "pux", "ulyuk"]

# Har bir mahsulotning O'ZIGA XOS rangi — frontend/lib/theme.dart'dagi
# `mahsulotRanglari` bilan BIR XIL "to'q" (dark) qiymatlar (rang izchilligi
# ilova va Excel eksporti orasida saqlansin uchun). "och" — sarlavha foni
# uchun shu rangning ochiq (light tint) varianti, "jami" — JAMI qatori foni
# uchun bir oz to'qroq (lekin hamon och) oraliq tint — sarlavhadan ANIQ farq
# qilib, baribir o'sha mahsulot rang oilasida qoladi.
_MAHSULOT_RANGLARI = {
    "tola": {"toq": "0F6E56", "och": "E6F4F0", "jami": "C3DBD5"},
    "lint": {"toq": "3B82C4", "och": "EBF3F9", "jami": "CEE0F0"},
    "pux": {"toq": "D98B2B", "och": "FBF3EA", "jami": "F6E2CA"},
    "ulyuk": {"toq": "8B5FBF", "och": "F3EFF9", "jami": "E2D7EF"},
}
_STANDART_RANG = _MAHSULOT_RANGLARI["tola"]  # mahsulot kodi ro'yxatda topilmasa — zaxira

# Ustunlar: Kip №, Partiya №, Vaqt, Og'irlik (kg), Operator — auto-fit
# hisoblanadi (haqiqiy matn uzunligiga qarab), lekin bu qiymatlardan
# TORROQ bo'lmaydi (sarlavha matni hech qachon kesilmasin uchun).
_USTUN_MINIMAL_KENGLIKLARI = [10, 12, 12, 14, 18]

_YUPQA_CHEGARA = Side(style="thin", color="B7B7B7")
_HUJAYRA_CHEGARASI = Border(left=_YUPQA_CHEGARA, right=_YUPQA_CHEGARA, top=_YUPQA_CHEGARA, bottom=_YUPQA_CHEGARA)


def _mahsulot_rangi(mahsulot_kodi: str) -> dict:
    return _MAHSULOT_RANGLARI.get(mahsulot_kodi, _STANDART_RANG)


def _chegaralarni_qoy(ws: Worksheet, boshlanish_qatori: int) -> None:
    """`boshlanish_qatori`dan (1-asosli) joriy oxirgi qatorgacha, barcha
    ishlatilgan ustunlardagi har bir katakchaga yupqa chegara chizadi."""
    for qator in ws.iter_rows(min_row=boshlanish_qatori, max_row=ws.max_row, max_col=ws.max_column):
        for hujayra in qator:
            hujayra.border = _HUJAYRA_CHEGARASI


def _ustunlarni_avtomoslash(ws: Worksheet, boshlanish_qatori: int, minimal_kengliklar: list[int]) -> None:
    """Har ustun uchun — `boshlanish_qatori`dan boshlab shu ustundagi ENG
    UZUN matn ko'rinishiga (+ozgina bo'sh joy) qarab kenglik belgilaydi, lekin
    mos `minimal_kengliklar`dan TORROQ bo'lishiga yo'l qo'ymaydi."""
    for i, minimal in enumerate(minimal_kengliklar, start=1):
        eng_uzuni = minimal
        for qator in ws.iter_rows(min_row=boshlanish_qatori, max_row=ws.max_row, min_col=i, max_col=i):
            qiymat = qator[0].value
            if qiymat is None:
                continue
            eng_uzuni = max(eng_uzuni, len(str(qiymat)) + 2)
        ws.column_dimensions[get_column_letter(i)].width = eng_uzuni


def smena_mahsulot_jadval(db: Session, sana: date, smena: Smena, mahsulot: Mahsulot) -> Workbook:
    """Bitta KUN + bitta SMENA + bitta MAHSULOT uchun tor eksport — shu
    kombinatsiyada tortilgan har bir kip alohida qator (kip raqami, partiya,
    vaqt, kg, operator) va oxirida JAMI qatori. Faqat HISOBLANADIGAN
    holatdagi kiplar (bekor qilinganlar chiqarib tashlanadi).

    Vizual: sarlavha qatori mahsulotning O'ZIGA XOS rangida (och fon + to'q
    matn, `_MAHSULOT_RANGLARI` — frontend bilan izchil), barcha katakchalar
    chegaralangan, ustun kengliklari mazmunga qarab avtomoslashtirilgan."""
    rang = _mahsulot_rangi(mahsulot.kod)
    pastki, yuqori = sargable_oraliq(sana, sana)
    qatorlar = db.execute(
        select(Kip.kip_raqami, Kip.vaqt, Kip.ogirlik, Partiya.partiya_raqami, Foydalanuvchi.ism)
        .join(Partiya, Partiya.id == Kip.partiya_id)
        .join(Foydalanuvchi, Foydalanuvchi.id == Kip.operator_id)
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

    sarlavha_qatori = ws.max_row + 1
    ws.append(["Kip №", "Partiya №", "Vaqt", "Og'irlik, kg", "Operator"])
    sarlavha_foni = PatternFill("solid", fgColor=rang["och"])
    for hujayra in ws[ws.max_row]:
        hujayra.font = Font(bold=True, color=rang["toq"])
        hujayra.fill = sarlavha_foni

    jami_kg = 0.0
    for kip_raqami, vaqt, ogirlik, partiya_raqami, operator_ism in qatorlar:
        ws.append([kip_raqami, partiya_raqami, vaqt.strftime("%H:%M:%S"), round(float(ogirlik), 2), operator_ism])
        jami_kg += float(ogirlik)

    ws.append([f"JAMI ({len(qatorlar)} kip)", "", "", round(jami_kg, 2), ""])
    jami_foni = PatternFill("solid", fgColor=rang["jami"])
    for hujayra in ws[ws.max_row]:
        hujayra.font = Font(bold=True, color=rang["toq"])
        hujayra.fill = jami_foni

    _chegaralarni_qoy(ws, sarlavha_qatori)
    _ustunlarni_avtomoslash(ws, sarlavha_qatori, _USTUN_MINIMAL_KENGLIKLARI)

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

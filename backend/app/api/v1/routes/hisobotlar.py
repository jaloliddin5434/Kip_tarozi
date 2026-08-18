from datetime import date
from io import BytesIO

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import StreamingResponse
from openpyxl import Workbook
from openpyxl.styles import Font
from openpyxl.utils import get_column_letter
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import rollarga_ruxsat
from app.core.database import get_db
from app.models.foydalanuvchi import Foydalanuvchi, Rol, Smena
from app.models.kip import Kip, KipHolati
from app.models.mahsulot import Mahsulot
from app.models.partiya import Partiya

router = APIRouter(prefix="/hisobotlar", tags=["hisobotlar"])

_MAHSULOT_TARTIBI = ["tola", "lint", "pux", "ulyuk"]


@router.get("/smena-excel")
def smena_excel(
    sana: date = Query(...),
    smena: Smena = Query(...),
    db: Session = Depends(get_db),
    foydalanuvchi: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.admin, Rol.operator)),
) -> StreamingResponse:
    if foydalanuvchi.rol == Rol.operator and foydalanuvchi.smena != smena:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Faqat o'z smenangiz hisobotini olishingiz mumkin",
        )

    mahsulotlar = db.execute(select(Mahsulot.kod, Mahsulot.nomi)).all()
    nomlar = {kod: nomi for kod, nomi in mahsulotlar}

    qatorlar = db.execute(
        select(Mahsulot.kod, func.count(Kip.id), func.coalesce(func.sum(Kip.ogirlik), 0))
        .join(Partiya, Partiya.mahsulot_id == Mahsulot.id)
        .join(Kip, Kip.partiya_id == Partiya.id)
        .where(Kip.holati == KipHolati.aktiv, Kip.smena == smena, func.date(Kip.vaqt) == sana)
        .group_by(Mahsulot.kod)
    ).all()
    jamlanma = {kod: (soni, float(kg)) for kod, soni, kg in qatorlar}

    wb = Workbook()
    ws = wb.active
    ws.title = f"Smena {smena.value}"

    ws.append(["Mahsulot", "Soni", "Jami kg", "O'rtacha kg"])
    for hujayra in ws[1]:
        hujayra.font = Font(bold=True)

    jami_soni = 0
    jami_kg = 0.0
    for kod in _MAHSULOT_TARTIBI:
        soni, kg = jamlanma.get(kod, (0, 0.0))
        ortacha = round(kg / soni, 2) if soni else 0.0
        ws.append([nomlar.get(kod, kod), soni, round(kg, 2), ortacha])
        jami_soni += soni
        jami_kg += kg

    jami_ortacha = round(jami_kg / jami_soni, 2) if jami_soni else 0.0
    ws.append(["JAMI", jami_soni, round(jami_kg, 2), jami_ortacha])
    for hujayra in ws[ws.max_row]:
        hujayra.font = Font(bold=True)

    for i, kenglik in enumerate([20, 10, 12, 14], start=1):
        ws.column_dimensions[get_column_letter(i)].width = kenglik

    buffer = BytesIO()
    wb.save(buffer)
    buffer.seek(0)

    fayl_nomi = f"Smena_{smena.value}_{sana.isoformat()}.xlsx"
    return StreamingResponse(
        buffer,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="{fayl_nomi}"'},
    )

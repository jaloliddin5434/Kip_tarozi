from datetime import datetime, timezone

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import agent_autentifikatsiya, rollarga_ruxsat
from app.core.database import get_db
from app.models.foydalanuvchi import Foydalanuvchi, Rol, Smena
from app.models.shubhali_holat import ShubhaliHolat, ShubhaliHolatStatusi
from app.schemas.shubhali_holat import ShubhaliHolatJavob
from app.services.storage.rasm import rasm_saqla
from app.services.telegram import xatolik_xabari

router = APIRouter(prefix="/shubhali-holatlar", tags=["shubhali-holatlar"])


@router.post("", response_model=ShubhaliHolatJavob, status_code=status.HTTP_201_CREATED)
async def hodisa_royxatga_ol(
    ogirlik: float = Form(...),
    vaqt: datetime = Form(...),
    smena: str | None = Form(None),
    mahsulot_kodi: str | None = Form(None),
    surat: UploadFile | None = File(None),
    db: Session = Depends(get_db),
    _: None = Depends(agent_autentifikatsiya),
) -> ShubhaliHolat:
    """Stansiya Agenti anti-o'g'irlik state machine'i 'yuk saqlanmadi' hodisasini
    aniqlaganda shu endpointga murojaat qiladi (foydalanuvchi tokeni bilan emas,
    doimiy AGENT_API_KEY bilan — chunki bu operator amalidan mustaqil, avtomatik amal)."""

    smena_enum = Smena(smena) if smena else None

    surat_yoli = None
    if surat is not None:
        baytlar = await surat.read()
        surat_yoli = rasm_saqla(
            baytlar, mahsulot_kodi=mahsulot_kodi or "umumiy", smena=smena or "umumiy", vaqt=vaqt, turi="shubha"
        )

    hodisa = ShubhaliHolat(vaqt=vaqt, smena=smena_enum, ogirlik=ogirlik, surat_yoli=surat_yoli)
    db.add(hodisa)
    db.commit()
    db.refresh(hodisa)

    smena_matni = smena or "noma'lum"
    xatolik_xabari(db, f"⚠️ YUK SAQLANMADI!\nSmena: {smena_matni}\nOg'irlik: {ogirlik} kg\nVaqt: {vaqt.isoformat()}")
    return hodisa


@router.get("/bloklovchi", response_model=ShubhaliHolatJavob | None)
def bloklovchini_tekshir(
    db: Session = Depends(get_db),
    foydalanuvchi: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.operator)),
) -> ShubhaliHolat | None:
    return db.scalar(
        select(ShubhaliHolat)
        .where(ShubhaliHolat.holati == ShubhaliHolatStatusi.yangi, ShubhaliHolat.smena == foydalanuvchi.smena)
        .order_by(ShubhaliHolat.vaqt.desc())
        .limit(1)
    )


@router.patch("/{hodisa_id}/tasdiqla", response_model=ShubhaliHolatJavob)
def tasdiqlash(
    hodisa_id: int,
    db: Session = Depends(get_db),
    foydalanuvchi: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.operator, Rol.admin)),
) -> ShubhaliHolat:
    hodisa = db.get(ShubhaliHolat, hodisa_id)
    if hodisa is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Hodisa topilmadi")

    hodisa.holati = ShubhaliHolatStatusi.korib_chiqildi
    hodisa.korib_chiqqan_id = foydalanuvchi.id
    hodisa.korib_chiqilgan_vaqt = datetime.now(timezone.utc)
    db.commit()
    db.refresh(hodisa)
    return hodisa

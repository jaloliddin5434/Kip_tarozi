from datetime import date, datetime, timezone

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import agent_autentifikatsiya, rollarga_ruxsat
from app.core.database import get_db
from app.models.foydalanuvchi import Foydalanuvchi, Rol, Smena
from app.models.shubhali_holat import ShubhaliHolat, ShubhaliHolatStatusi
from app.schemas.sahifalash import Sahifalangan
from app.schemas.shubhali_holat import ShubhaliHolatJavob, ShubhaliHolatRoyxatJavob
from app.services.storage.rasm import rasm_saqla
from app.services.telegram import xatolik_xabari

router = APIRouter(prefix="/shubhali-holatlar", tags=["shubhali-holatlar"])


@router.post("", response_model=ShubhaliHolatJavob, status_code=status.HTTP_201_CREATED)
async def hodisa_royxatga_ol(
    ogirlik: float = Form(...),
    vaqt: datetime = Form(...),
    smena: str | None = Form(None),
    mahsulot_kodi: str | None = Form(None),
    stansiya_id: int | None = Form(None),
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

    hodisa = ShubhaliHolat(vaqt=vaqt, smena=smena_enum, ogirlik=ogirlik, surat_yoli=surat_yoli, stansiya_id=stansiya_id)
    db.add(hodisa)
    db.commit()
    db.refresh(hodisa)

    smena_matni = smena or "noma'lum"
    xatolik_xabari(db, f"⚠️ YUK SAQLANMADI!\nSmena: {smena_matni}\nOg'irlik: {ogirlik} kg\nVaqt: {vaqt.isoformat()}")
    return hodisa


@router.get("", response_model=Sahifalangan[ShubhaliHolatRoyxatJavob])
def royxat(
    sana_dan: date | None = Query(None),
    sana_gacha: date | None = Query(None),
    smena: Smena | None = Query(None),
    holati: ShubhaliHolatStatusi | None = Query(None),
    sahifa: int = Query(1, ge=1),
    sahifa_hajmi: int = Query(50, ge=1, le=500),
    db: Session = Depends(get_db),
    _: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.admin)),
) -> Sahifalangan[ShubhaliHolatRoyxatJavob]:
    """Admin panel — barcha 'yuk saqlanmadi' hodisalari, filtr bilan. Smena/vaqt
    bo'yicha statistika shu ro'yxatni filtrlash orqali olinadi (masalan
    smena=A bilan filtrlab, `jami` maydonidan shu smenadagi hodisalar sonini
    ko'rish mumkin)."""
    korib_chiqqan = Foydalanuvchi.__table__.alias("korib_chiqqan")

    sorov = select(ShubhaliHolat, korib_chiqqan.c.ism).outerjoin(
        korib_chiqqan, ShubhaliHolat.korib_chiqqan_id == korib_chiqqan.c.id
    )
    if sana_dan is not None:
        sorov = sorov.where(func.date(ShubhaliHolat.vaqt) >= sana_dan)
    if sana_gacha is not None:
        sorov = sorov.where(func.date(ShubhaliHolat.vaqt) <= sana_gacha)
    if smena is not None:
        sorov = sorov.where(ShubhaliHolat.smena == smena)
    if holati is not None:
        sorov = sorov.where(ShubhaliHolat.holati == holati)

    jami = db.scalar(select(func.count()).select_from(sorov.subquery())) or 0

    sahifalangan_sorov = (
        sorov.order_by(ShubhaliHolat.vaqt.desc()).offset((sahifa - 1) * sahifa_hajmi).limit(sahifa_hajmi)
    )
    natijalar = db.execute(sahifalangan_sorov).all()

    items = [
        ShubhaliHolatRoyxatJavob(
            id=hodisa.id,
            vaqt=hodisa.vaqt,
            smena=hodisa.smena,
            ogirlik=float(hodisa.ogirlik),
            surat_yoli=hodisa.surat_yoli,
            holati=hodisa.holati,
            korib_chiqqan_id=hodisa.korib_chiqqan_id,
            korib_chiqilgan_vaqt=hodisa.korib_chiqilgan_vaqt,
            stansiya_id=hodisa.stansiya_id,
            korib_chiqqan_ism=ism,
        )
        for hodisa, ism in natijalar
    ]
    return Sahifalangan(items=items, jami=jami, sahifa=sahifa, sahifa_hajmi=sahifa_hajmi)


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

from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import joriy_moliyaviy_foydalanuvchi, rollarga_ruxsat
from app.core.config import settings
from app.core.database import get_db
from app.core.security import parolni_hash, parolni_tekshir, token_yarat
from app.models.foydalanuvchi import Foydalanuvchi, Rol
from app.models.mahsulot import Mahsulot
from app.models.partiya import Partiya, PartiyaHolati
from app.models.sozlama import Sozlama
from app.schemas.moliyaviy import MoliyaviyHisobot, MoliyaviyKirish, MoliyaviyMahsulotHisoboti, MoliyaviyToken, UzexNarxJavob
from app.services.davr import davr_oraligi
from app.services.uzex import uzex_narxlari

router = APIRouter(prefix="/moliyaviy", tags=["moliyaviy"])

MOLIYAVIY_PAROL_KALITI = "moliyaviy_parol_hash"


@router.post("/parolni-ornatish")
def parolni_ornatish(
    malumot: MoliyaviyKirish,
    db: Session = Depends(get_db),
    _: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.admin)),
) -> dict:
    """Moliyaviy bo'lim qo'shimcha parolini (qayta) o'rnatadi — oddiy Admin
    tokeni yetarli (bu moliyaviy sessiya emas, faqat parolni almashtirish)."""
    if len(malumot.parol) < 4:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Parol kamida 4 belgidan iborat bo'lishi kerak")

    parol_hash = parolni_hash(malumot.parol)
    sozlama = db.get(Sozlama, MOLIYAVIY_PAROL_KALITI)
    if sozlama is None:
        db.add(Sozlama(kalit=MOLIYAVIY_PAROL_KALITI, qiymat=parol_hash, tavsif="Moliyaviy bo'lim qo'shimcha paroli (hash)"))
    else:
        sozlama.qiymat = parol_hash
    db.commit()
    return {"holat": "ok"}


@router.post("/kirish", response_model=MoliyaviyToken)
def kirish(
    malumot: MoliyaviyKirish,
    db: Session = Depends(get_db),
    foydalanuvchi: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.admin)),
) -> MoliyaviyToken:
    sozlama = db.get(Sozlama, MOLIYAVIY_PAROL_KALITI)
    if sozlama is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Moliyaviy parol hali sozlanmagan — avval POST /moliyaviy/parolni-ornatish orqali o'rnating",
        )
    if not parolni_tekshir(malumot.parol, sozlama.qiymat):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Moliyaviy parol noto'g'ri")

    token = token_yarat(
        {"sub": str(foydalanuvchi.id), "rol": foydalanuvchi.rol.value, "moliyaviy": True},
        muddat_daqiqa=settings.MOLIYAVIY_TOKEN_MUDDATI_DAQIQA,
    )
    return MoliyaviyToken(access_token=token, muddat_daqiqa=settings.MOLIYAVIY_TOKEN_MUDDATI_DAQIQA)


@router.get("/uzex-narxlar", response_model=list[UzexNarxJavob])
def uzex_narxlar(_: Foydalanuvchi = Depends(joriy_moliyaviy_foydalanuvchi)) -> list[UzexNarxJavob]:
    """UZEX (uzex.uz) dan paxta tolasi va yon mahsulotlari uchun joriy narxlar
    (so'm/kg). Natija 1 soat keshlanadi; UZEX bilan aloqa uzilsa, oxirgi
    muvaffaqiyatli qiymatlarga (yoki zaxira qiymatlarga) qaytiladi.
    `yangilangan_vaqt` — haqiqiy oxirgi muvaffaqiyatli olingan vaqt."""
    narxlar, yangilangan_vaqt = uzex_narxlari()
    return [
        UzexNarxJavob(mahsulot_kodi=kod, mahsulot_nomi=nomi, narx_som=narx, yangilangan_vaqt=yangilangan_vaqt)
        for kod, nomi, narx in narxlar
    ]


@router.get("/hisobot", response_model=MoliyaviyHisobot)
def hisobot(
    davr: str = Query("oylik"),
    sana: date = Query(default_factory=date.today),
    db: Session = Depends(get_db),
    _: Foydalanuvchi = Depends(joriy_moliyaviy_foydalanuvchi),
) -> MoliyaviyHisobot:
    if davr not in ("kunlik", "haftalik", "oylik", "mavsum"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Noma'lum davr: {davr}")
    boshlanish, tugash = davr_oraligi(davr, sana, db)

    qatorlar = db.execute(
        select(
            Mahsulot.kod,
            Mahsulot.nomi,
            func.count(Partiya.id),
            func.coalesce(func.sum(Partiya.sof_vazn), 0),
            func.coalesce(func.sum(Partiya.sotuv_narxi), 0),
        )
        .join(Partiya, Partiya.mahsulot_id == Mahsulot.id)
        .where(
            Partiya.holati == PartiyaHolati.sotilgan,
            Partiya.sotuv_sanasi >= boshlanish,
            Partiya.sotuv_sanasi <= tugash,
        )
        .group_by(Mahsulot.kod, Mahsulot.nomi)
    ).all()

    mahsulotlar = [
        MoliyaviyMahsulotHisoboti(
            mahsulot_kodi=kod, mahsulot_nomi=nomi, partiyalar_soni=soni, jami_sof_vazn=float(vazn), jami_summa=float(summa)
        )
        for kod, nomi, soni, vazn, summa in qatorlar
    ]
    return MoliyaviyHisobot(
        davr=davr,
        boshlanish_sanasi=boshlanish,
        tugash_sanasi=tugash,
        mahsulotlar=mahsulotlar,
        jami_summa=sum(m.jami_summa for m in mahsulotlar),
    )

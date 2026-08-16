from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import rollarga_ruxsat
from app.core.database import get_db
from app.models.foydalanuvchi import Foydalanuvchi, Rol, Smena
from app.models.kip import Kip, KipHolati
from app.models.mahsulot import Mahsulot
from app.models.partiya import Partiya
from app.schemas.statistika import DavrJamlanmasi, MahsulotJamlanmasi, OperatorJamlanmasi, SmenaJamlanmasi
from app.services.davr import davr_oraligi

router = APIRouter(prefix="/statistika", tags=["statistika"])

DAVRLAR = ("kunlik", "haftalik", "oylik", "mavsum")


def _davrni_tekshir(davr: str) -> None:
    if davr not in DAVRLAR:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Noma'lum davr: {davr}. Ruxsat etilgan: {', '.join(DAVRLAR)}",
        )


@router.get("/jamlanma", response_model=DavrJamlanmasi)
def jamlanma(
    davr: str = Query("kunlik"),
    sana: date = Query(default_factory=date.today),
    smena: Smena | None = Query(None),
    db: Session = Depends(get_db),
    _: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.admin)),
) -> DavrJamlanmasi:
    _davrni_tekshir(davr)
    boshlanish, tugash = davr_oraligi(davr, sana)

    qatorlar = db.execute(
        select(
            Mahsulot.kod,
            Mahsulot.nomi,
            func.count(Kip.id),
            func.coalesce(func.sum(Kip.ogirlik), 0),
        )
        .join(Partiya, Partiya.mahsulot_id == Mahsulot.id)
        .join(Kip, Kip.partiya_id == Partiya.id)
        .where(
            Kip.holati == KipHolati.aktiv,
            func.date(Kip.vaqt) >= boshlanish,
            func.date(Kip.vaqt) <= tugash,
            *([Kip.smena == smena] if smena is not None else []),
        )
        .group_by(Mahsulot.kod, Mahsulot.nomi)
    ).all()

    mahsulotlar = [
        MahsulotJamlanmasi(mahsulot_kodi=kod, mahsulot_nomi=nomi, soni=soni, jami_kg=float(kg))
        for kod, nomi, soni, kg in qatorlar
    ]
    return DavrJamlanmasi(
        davr=davr,
        boshlanish_sanasi=boshlanish,
        tugash_sanasi=tugash,
        mahsulotlar=mahsulotlar,
        jami_soni=sum(m.soni for m in mahsulotlar),
        jami_kg=sum(m.jami_kg for m in mahsulotlar),
    )


@router.get("/smena-boyicha", response_model=list[SmenaJamlanmasi])
def smena_boyicha(
    davr: str = Query("kunlik"),
    sana: date = Query(default_factory=date.today),
    db: Session = Depends(get_db),
    _: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.admin)),
) -> list[SmenaJamlanmasi]:
    _davrni_tekshir(davr)
    boshlanish, tugash = davr_oraligi(davr, sana)

    qatorlar = db.execute(
        select(Kip.smena, func.count(Kip.id), func.coalesce(func.sum(Kip.ogirlik), 0))
        .where(
            Kip.holati == KipHolati.aktiv,
            func.date(Kip.vaqt) >= boshlanish,
            func.date(Kip.vaqt) <= tugash,
        )
        .group_by(Kip.smena)
        .order_by(Kip.smena)
    ).all()

    return [SmenaJamlanmasi(smena=smena.value, soni=soni, jami_kg=float(kg)) for smena, soni, kg in qatorlar]


@router.get("/operator-boyicha", response_model=list[OperatorJamlanmasi])
def operator_boyicha(
    davr: str = Query("kunlik"),
    sana: date = Query(default_factory=date.today),
    db: Session = Depends(get_db),
    _: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.admin)),
) -> list[OperatorJamlanmasi]:
    _davrni_tekshir(davr)
    boshlanish, tugash = davr_oraligi(davr, sana)

    qatorlar = db.execute(
        select(
            Foydalanuvchi.id,
            Foydalanuvchi.ism,
            Foydalanuvchi.login,
            Foydalanuvchi.smena,
            func.count(Kip.id),
            func.coalesce(func.sum(Kip.ogirlik), 0),
        )
        .join(Kip, Kip.operator_id == Foydalanuvchi.id)
        .where(
            Kip.holati == KipHolati.aktiv,
            func.date(Kip.vaqt) >= boshlanish,
            func.date(Kip.vaqt) <= tugash,
        )
        .group_by(Foydalanuvchi.id, Foydalanuvchi.ism, Foydalanuvchi.login, Foydalanuvchi.smena)
        .order_by(func.sum(Kip.ogirlik).desc())
    ).all()

    return [
        OperatorJamlanmasi(
            operator_id=op_id,
            ism=ism,
            login=login,
            smena=smena.value if smena else None,
            soni=soni,
            jami_kg=float(kg),
        )
        for op_id, ism, login, smena, soni, kg in qatorlar
    ]

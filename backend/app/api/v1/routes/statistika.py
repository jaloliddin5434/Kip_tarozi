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
from app.schemas.statistika import (
    DavrJamlanmasi,
    MahsulotJamlanmasi,
    OperatorJamlanmasi,
    RekordKun,
    RekordlarJavob,
    RekordOperator,
    RekordSmena,
    SmenaJamlanmasi,
)
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
    mahsulot_kodi: str | None = Query(None),
    db: Session = Depends(get_db),
    _: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.admin)),
) -> list[SmenaJamlanmasi]:
    _davrni_tekshir(davr)
    boshlanish, tugash = davr_oraligi(davr, sana)

    sorov = select(Kip.smena, func.count(Kip.id), func.coalesce(func.sum(Kip.ogirlik), 0))
    if mahsulot_kodi is not None:
        sorov = sorov.join(Partiya, Partiya.id == Kip.partiya_id).join(Mahsulot, Mahsulot.id == Partiya.mahsulot_id)
    sorov = sorov.where(
        Kip.holati == KipHolati.aktiv,
        func.date(Kip.vaqt) >= boshlanish,
        func.date(Kip.vaqt) <= tugash,
        *([Mahsulot.kod == mahsulot_kodi] if mahsulot_kodi is not None else []),
    ).group_by(Kip.smena).order_by(Kip.smena)

    qatorlar = db.execute(sorov).all()

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


@router.get("/rekordlar", response_model=RekordlarJavob)
def rekordlar(
    davr: str = Query("mavsum"),
    sana: date = Query(default_factory=date.today),
    db: Session = Depends(get_db),
    _: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.admin)),
) -> RekordlarJavob:
    """"Rekord" paneli: tanlangan davr uchun eng yaxshi smena (kg bo'yicha)
    va eng yaxshi operator (kip soni bo'yicha), hamda BARCHA VAQT bo'yicha
    bir kundagi eng yuqori jami kg. Ma'lumot bo'lmasa tegishli maydon null."""
    _davrni_tekshir(davr)
    boshlanish, tugash = davr_oraligi(davr, sana)

    davr_sharti = (
        Kip.holati == KipHolati.aktiv,
        func.date(Kip.vaqt) >= boshlanish,
        func.date(Kip.vaqt) <= tugash,
    )

    smena_qatori = db.execute(
        select(Kip.smena, func.coalesce(func.sum(Kip.ogirlik), 0))
        .where(*davr_sharti)
        .group_by(Kip.smena)
        .order_by(func.sum(Kip.ogirlik).desc())
        .limit(1)
    ).first()
    eng_yaxshi_smena = (
        RekordSmena(smena=smena_qatori[0].value, jami_kg=float(smena_qatori[1]))
        if smena_qatori and smena_qatori[1]
        else None
    )

    operator_qatori = db.execute(
        select(Foydalanuvchi.id, Foydalanuvchi.ism, Foydalanuvchi.login, func.count(Kip.id))
        .join(Kip, Kip.operator_id == Foydalanuvchi.id)
        .where(*davr_sharti)
        .group_by(Foydalanuvchi.id, Foydalanuvchi.ism, Foydalanuvchi.login)
        .order_by(func.count(Kip.id).desc())
        .limit(1)
    ).first()
    eng_yaxshi_operator = (
        RekordOperator(operator_id=operator_qatori[0], ism=operator_qatori[1], login=operator_qatori[2], soni=operator_qatori[3])
        if operator_qatori and operator_qatori[3]
        else None
    )

    # DIQQAT: bu so'rov davrga BOG'LIQ EMAS — barcha vaqt bo'yicha eng
    # yuqori kunlik yig'im (bitta kalendar kundagi jami kg).
    kun_ustuni = func.date(Kip.vaqt)
    kun_qatori = db.execute(
        select(kun_ustuni, func.coalesce(func.sum(Kip.ogirlik), 0))
        .where(Kip.holati == KipHolati.aktiv)
        .group_by(kun_ustuni)
        .order_by(func.sum(Kip.ogirlik).desc())
        .limit(1)
    ).first()
    eng_yuqori_kunlik_yigim = None
    if kun_qatori and kun_qatori[1]:
        kun = kun_qatori[0]
        kun = kun if isinstance(kun, date) else date.fromisoformat(str(kun))
        eng_yuqori_kunlik_yigim = RekordKun(sana=kun, jami_kg=float(kun_qatori[1]))

    return RekordlarJavob(
        davr=davr,
        boshlanish_sanasi=boshlanish,
        tugash_sanasi=tugash,
        eng_yaxshi_smena=eng_yaxshi_smena,
        eng_yaxshi_operator=eng_yaxshi_operator,
        eng_yuqori_kunlik_yigim=eng_yuqori_kunlik_yigim,
    )

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import rollarga_ruxsat
from app.core.database import get_db
from app.models.foydalanuvchi import Foydalanuvchi, Rol
from app.models.kip import Kip, KipHolati
from app.models.mahsulot import Mahsulot
from app.models.partiya import Partiya, PartiyaHolati
from app.schemas.partiya import PartiyaJavob, PartiyaOchish, PartiyaSotish
from app.schemas.sahifalash import Sahifalangan
from app.services.hujjatlar.nakladnoy import nakladnoy_pdf_yarat, nakladnoy_raqami_yarat

router = APIRouter(prefix="/partiyalar", tags=["partiyalar"])


def _javobga_ayirib(db: Session, partiya: Partiya, mahsulot: Mahsulot) -> PartiyaJavob:
    jamlanma = db.execute(
        select(func.count(Kip.id), func.coalesce(func.sum(Kip.ogirlik), 0)).where(
            Kip.partiya_id == partiya.id, Kip.holati == KipHolati.aktiv
        )
    ).one()
    return PartiyaJavob(
        id=partiya.id,
        mahsulot_id=partiya.mahsulot_id,
        mahsulot_kodi=mahsulot.kod,
        mahsulot_nomi=mahsulot.nomi,
        partiya_raqami=partiya.partiya_raqami,
        holati=partiya.holati,
        yaratilgan_vaqt=partiya.yaratilgan_vaqt,
        yopilgan_vaqt=partiya.yopilgan_vaqt,
        kip_soni=jamlanma[0],
        jami_kg=float(jamlanma[1]),
        sotuv_sanasi=partiya.sotuv_sanasi,
        xaridor=partiya.xaridor,
        dogovor_raqami=partiya.dogovor_raqami,
        sort=partiya.sort,
        urama_bilan_vazn=float(partiya.urama_bilan_vazn) if partiya.urama_bilan_vazn is not None else None,
        urama_vazni=float(partiya.urama_vazni) if partiya.urama_vazni is not None else None,
        sof_vazn=float(partiya.sof_vazn) if partiya.sof_vazn is not None else None,
        kondicion_vazni=float(partiya.kondicion_vazni) if partiya.kondicion_vazni is not None else None,
        sotuv_narxi=float(partiya.sotuv_narxi) if partiya.sotuv_narxi is not None else None,
        nakladnoy_raqami=partiya.nakladnoy_raqami,
        nakladnoy_pdf_yoli=partiya.nakladnoy_pdf_yoli,
    )


@router.post("", response_model=PartiyaJavob)
def ochish_yoki_tanlash(
    malumot: PartiyaOchish,
    db: Session = Depends(get_db),
    foydalanuvchi: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.operator, Rol.admin)),
) -> PartiyaJavob:
    if malumot.partiya_raqami < 1:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Partiya raqami majburiy va musbat bo'lishi kerak")

    mahsulot = db.scalar(select(Mahsulot).where(Mahsulot.kod == malumot.mahsulot_kodi, Mahsulot.faol.is_(True)))
    if mahsulot is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Mahsulot topilmadi")

    partiya = db.scalar(
        select(Partiya).where(Partiya.mahsulot_id == mahsulot.id, Partiya.partiya_raqami == malumot.partiya_raqami)
    )
    if partiya is None:
        partiya = Partiya(
            mahsulot_id=mahsulot.id,
            partiya_raqami=malumot.partiya_raqami,
            holati=PartiyaHolati.ochiq,
            yaratgan_id=foydalanuvchi.id,
        )
        db.add(partiya)
        db.commit()
        db.refresh(partiya)
    elif partiya.holati != PartiyaHolati.ochiq:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Partiya #{malumot.partiya_raqami} allaqachon {partiya.holati.value} — kip qo'sha olmaysiz",
        )

    return _javobga_ayirib(db, partiya, mahsulot)


@router.get("", response_model=Sahifalangan[PartiyaJavob])
def royxat(
    mahsulot_kodi: str | None = Query(None),
    holati: PartiyaHolati | None = Query(None),
    sahifa: int = Query(1, ge=1),
    sahifa_hajmi: int = Query(50, ge=1, le=500),
    db: Session = Depends(get_db),
    _: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.admin, Rol.tayyor_mahsulotlar)),
) -> Sahifalangan[PartiyaJavob]:
    sorov = select(Partiya).join(Mahsulot, Partiya.mahsulot_id == Mahsulot.id)
    if mahsulot_kodi is not None:
        sorov = sorov.where(Mahsulot.kod == mahsulot_kodi)
    if holati is not None:
        sorov = sorov.where(Partiya.holati == holati)

    jami = db.scalar(select(func.count()).select_from(sorov.subquery())) or 0

    sahifalangan_sorov = (
        sorov.order_by(Partiya.yaratilgan_vaqt.desc()).offset((sahifa - 1) * sahifa_hajmi).limit(sahifa_hajmi)
    )
    partiyalar = db.scalars(sahifalangan_sorov).all()

    items = [_javobga_ayirib(db, p, db.get(Mahsulot, p.mahsulot_id)) for p in partiyalar]
    return Sahifalangan(items=items, jami=jami, sahifa=sahifa, sahifa_hajmi=sahifa_hajmi)


@router.post("/{partiya_id}/sotish", response_model=PartiyaJavob)
def sotish(
    partiya_id: int,
    malumot: PartiyaSotish,
    db: Session = Depends(get_db),
    _: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.admin)),
) -> PartiyaJavob:
    partiya = db.get(Partiya, partiya_id)
    if partiya is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Partiya topilmadi")
    if partiya.holati != PartiyaHolati.yopiq:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Faqat yopilgan partiyani sotildi deb belgilash mumkin — avval partiyani yoping",
        )

    partiya.sotuv_sanasi = malumot.sotuv_sanasi
    partiya.xaridor = malumot.xaridor
    partiya.dogovor_raqami = malumot.dogovor_raqami
    partiya.sort = malumot.sort
    partiya.urama_bilan_vazn = malumot.urama_bilan_vazn
    partiya.urama_vazni = malumot.urama_vazni
    partiya.sof_vazn = malumot.sof_vazn
    partiya.kondicion_vazni = malumot.kondicion_vazni
    partiya.sotuv_narxi = malumot.sotuv_narxi
    partiya.holati = PartiyaHolati.sotilgan

    partiya.nakladnoy_raqami = nakladnoy_raqami_yarat(partiya)
    partiya.nakladnoy_pdf_yoli = nakladnoy_pdf_yarat(partiya)

    db.commit()
    db.refresh(partiya)

    mahsulot = db.get(Mahsulot, partiya.mahsulot_id)
    return _javobga_ayirib(db, partiya, mahsulot)


@router.get("/ochiq", response_model=list[PartiyaJavob])
def ochiq_royxat(
    mahsulot_kodi: str,
    db: Session = Depends(get_db),
    _: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.operator, Rol.admin)),
) -> list[PartiyaJavob]:
    mahsulot = db.scalar(select(Mahsulot).where(Mahsulot.kod == mahsulot_kodi))
    if mahsulot is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Mahsulot topilmadi")

    partiyalar = db.scalars(
        select(Partiya)
        .where(Partiya.mahsulot_id == mahsulot.id, Partiya.holati == PartiyaHolati.ochiq)
        .order_by(Partiya.partiya_raqami)
    )
    return [_javobga_ayirib(db, p, mahsulot) for p in partiyalar]


@router.patch("/{partiya_id}/yopish", response_model=PartiyaJavob)
def yopish(
    partiya_id: int,
    db: Session = Depends(get_db),
    foydalanuvchi: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.operator, Rol.admin)),
) -> PartiyaJavob:
    partiya = db.get(Partiya, partiya_id)
    if partiya is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Partiya topilmadi")
    if partiya.holati != PartiyaHolati.ochiq:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Partiya allaqachon yopiq")

    partiya.holati = PartiyaHolati.yopiq
    partiya.yopilgan_vaqt = datetime.now(timezone.utc)
    partiya.yopgan_id = foydalanuvchi.id
    db.commit()
    db.refresh(partiya)

    mahsulot = db.get(Mahsulot, partiya.mahsulot_id)
    return _javobga_ayirib(db, partiya, mahsulot)

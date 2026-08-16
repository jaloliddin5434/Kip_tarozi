from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import rollarga_ruxsat
from app.core.database import get_db
from app.models.foydalanuvchi import Foydalanuvchi, Rol
from app.models.kip import Kip, KipHolati
from app.models.mahsulot import Mahsulot
from app.models.partiya import Partiya, PartiyaHolati
from app.schemas.partiya import PartiyaJavob, PartiyaOchish

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

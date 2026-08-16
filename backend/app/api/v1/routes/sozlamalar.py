from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import rollarga_ruxsat
from app.core.database import get_db
from app.models.foydalanuvchi import Rol
from app.models.sozlama import Sozlama
from app.schemas.sozlama import SozlamaJavob, SozlamaYangilash

router = APIRouter(prefix="/sozlamalar", tags=["sozlamalar"])


@router.get("", response_model=list[SozlamaJavob])
def royxat(db: Session = Depends(get_db), _=Depends(rollarga_ruxsat(Rol.admin))) -> list[Sozlama]:
    return list(db.scalars(select(Sozlama).order_by(Sozlama.kalit)))


@router.get("/{kalit}", response_model=SozlamaJavob)
def olish(kalit: str, db: Session = Depends(get_db), _=Depends(rollarga_ruxsat(Rol.admin))) -> Sozlama:
    sozlama = db.get(Sozlama, kalit)
    if sozlama is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Sozlama topilmadi")
    return sozlama


@router.put("/{kalit}", response_model=SozlamaJavob)
def yangilash(
    kalit: str,
    malumot: SozlamaYangilash,
    db: Session = Depends(get_db),
    _=Depends(rollarga_ruxsat(Rol.admin)),
) -> Sozlama:
    sozlama = db.get(Sozlama, kalit)
    if sozlama is None:
        sozlama = Sozlama(kalit=kalit, qiymat=malumot.qiymat, tavsif=malumot.tavsif)
        db.add(sozlama)
    else:
        sozlama.qiymat = malumot.qiymat
        if malumot.tavsif is not None:
            sozlama.tavsif = malumot.tavsif
    db.commit()
    db.refresh(sozlama)
    return sozlama

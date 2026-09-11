from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import rollarga_ruxsat
from app.api.v1.routes.moliyaviy import MOLIYAVIY_PAROL_KALITI
from app.core.database import get_db
from app.models.foydalanuvchi import Rol
from app.models.sozlama import Sozlama
from app.schemas.sozlama import SozlamaJavob, SozlamaYangilash
from app.services.telegram import STATISTIKA_TOKEN_KALITI, SURAT_TOKEN_KALITI, XATOLIK_TOKEN_KALITI

router = APIRouter(prefix="/sozlamalar", tags=["sozlamalar"])

# AUDIT TOPILMASI (tuzatilmoqda): GET /sozlamalar barcha qiymatlarni,
# jumladan Telegram bot tokenlarini va moliyaviy parol hash'ini TO'LIQ
# MATNDA qaytarardi — brauzer DevTools Network orqali (yoki har qanday
# so'rovni ko'ra oladigan kishi) ularni to'liq o'qiy olardi. Endi shu
# kalitlar (aniq ro'yxat + "*_token"/"*_parol_hash" naqshi — kelajakda
# qo'shiladigan sozlamalar uchun ham) API JAVOBIDA maskalanadi. YOZISH
# (`PUT`) va backendning o'z ichki o'qishi (masalan `telegram.py`,
# `moliyaviy.py`) TO'LIQ qiymat bilan ishlashda davom etadi — faqat tashqi
# HTTP javobi o'zgaradi.
_MAXFIY_KALITLAR = {
    XATOLIK_TOKEN_KALITI,
    STATISTIKA_TOKEN_KALITI,
    SURAT_TOKEN_KALITI,
    MOLIYAVIY_PAROL_KALITI,
}
_MAXFIY_SUFFIKSLAR = ("_token", "_parol_hash")


def _maxfiymi(kalit: str) -> bool:
    return kalit in _MAXFIY_KALITLAR or kalit.endswith(_MAXFIY_SUFFIKSLAR)


def _maskalangan_qiymat(qiymat: str) -> str:
    """Bo'sh qiymat bo'sh qoladi; 4 belgidan uzun bo'lsa "••••" + oxirgi 4
    belgi (masalan tokenni operator/admin o'zi taniy olishi uchun); qisqa
    (<=4 belgi) qiymat esa umuman ochilmasdan to'liq "••••" bilan almashadi."""
    if not qiymat:
        return qiymat
    if len(qiymat) <= 4:
        return "••••"
    return "••••" + qiymat[-4:]


def _javobga_ayirib(sozlama: Sozlama) -> SozlamaJavob:
    qiymat = _maskalangan_qiymat(sozlama.qiymat) if _maxfiymi(sozlama.kalit) else sozlama.qiymat
    return SozlamaJavob(kalit=sozlama.kalit, qiymat=qiymat, tavsif=sozlama.tavsif, yangilangan_vaqt=sozlama.yangilangan_vaqt)


@router.get("", response_model=list[SozlamaJavob])
def royxat(db: Session = Depends(get_db), _=Depends(rollarga_ruxsat(Rol.admin))) -> list[SozlamaJavob]:
    return [_javobga_ayirib(s) for s in db.scalars(select(Sozlama).order_by(Sozlama.kalit))]


@router.get("/{kalit}", response_model=SozlamaJavob)
def olish(kalit: str, db: Session = Depends(get_db), _=Depends(rollarga_ruxsat(Rol.admin))) -> SozlamaJavob:
    sozlama = db.get(Sozlama, kalit)
    if sozlama is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Sozlama topilmadi")
    return _javobga_ayirib(sozlama)


@router.put("/{kalit}", response_model=SozlamaJavob)
def yangilash(
    kalit: str,
    malumot: SozlamaYangilash,
    db: Session = Depends(get_db),
    _=Depends(rollarga_ruxsat(Rol.admin)),
) -> SozlamaJavob:
    """Qabul qiladigan (`malumot.qiymat`) va bazaga yozadigan qiymat HAR
    DOIM TO'LIQ — admin yangi to'liq tokenni shu yerdan kiritadi. Faqat
    JAVOB (boshqa endpointlar bilan izchil) maxfiy kalitlar uchun
    maskalanadi."""
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
    return _javobga_ayirib(sozlama)

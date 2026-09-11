"""Saqlangan fayllarni (kip surati, shubhali holat surati, nakladnoy PDF)
AUTENTIFIKATSIYALANGAN holda beradi.

AUDIT TOPILMASI (tuzatilmoqda): ilgari `STORAGE_PATH` `StaticFiles` bilan
`/media`ga hech qanday tekshiruvsiz to'g'ridan-to'g'ri mount qilingan edi
(`app/main.py`) — bu orqali nakladnoy PDF'lar (`NK-000001.pdf`, ... ketma-ket,
taxmin qilinadigan nomlar — haqiqiy savdo hujjatlari) va barcha kip suratlari
token talab qilmasdan yuklab olinar edi. Endi:

- har so'rov JWT (`Authorization: Bearer ...`) talab qiladi;
- nakladnoy — faqat admin yoki tayyor_mahsulotlar (`/partiyalar/{id}/nakladnoy`
  bilan bir xil ruxsat qoidasi);
- kip/shubhali holat surati — istalgan autentifikatsiyalangan foydalanuvchi,
  lekin operator faqat O'Z SMENASIDAGI yozuvga tegishli suratni ko'radi
  (xuddi `GET /kiplar/{id}` va `GET /shubhali-holatlar/bloklovchi` qoidasi
  bilan bir xil);
- fayl yo'li HAR DOIM `STORAGE_PATH` ichida qolishi tekshiriladi (path
  traversal himoyasi, masalan `../../.env`).
"""

from pathlib import Path as SofYol

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import FileResponse
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import joriy_foydalanuvchi, rollarga_ruxsat
from app.core.config import settings
from app.core.database import get_db
from app.models.foydalanuvchi import Foydalanuvchi, Rol
from app.models.kip import Kip
from app.models.shubhali_holat import ShubhaliHolat

router = APIRouter(prefix="/media", tags=["media"])


def _xavfsiz_fayl(nisbiy_yol: str) -> SofYol:
    """`nisbiy_yol`ni (STORAGE_PATH'ga nisbiy) haqiqiy faylga aylantiradi.

    Natija STORAGE_PATH tashqarisiga chiqsa (masalan `../../.env`,
    `..\\..\\backend\\.env`) yoki fayl mavjud bo'lmasa — 404 (ikkalasida ham
    bir xil xato — fayl "yo'qligi" bilan "ruxsat yo'qligi" tashqaridan
    farqlanmasin)."""
    ildiz = SofYol(settings.STORAGE_PATH).resolve()
    nishon = (ildiz / nisbiy_yol).resolve()
    if not nishon.is_relative_to(ildiz) or not nishon.is_file():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Fayl topilmadi")
    return nishon


@router.get("/nakladnoy/{fayl_nomi}")
def nakladnoy_fayli(
    fayl_nomi: str,
    _: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.admin, Rol.tayyor_mahsulotlar)),
) -> FileResponse:
    """Savdo nakladnoy PDF'i. Fayl nomida yo'l ajratkichlar (`/`, `\\`)
    bo'lishi mumkin emas — faqat `nakladnoy/` papkasi ichidagi to'g'ridan-to'g'ri
    fayl nomi kutiladi (masalan `NK-000123.pdf`)."""
    if "/" in fayl_nomi or "\\" in fayl_nomi:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Fayl topilmadi")
    fayl = _xavfsiz_fayl(f"nakladnoy/{fayl_nomi}")
    return FileResponse(fayl, media_type="application/pdf")


def _surat_royxati_ruxsat(db: Session, foydalanuvchi: Foydalanuvchi, nisbiy_yol: str) -> bool:
    """Admin va tayyor_mahsulotlar — barcha suratlarni ko'radi. Operator —
    faqat O'Z SMENASIDAGI kip yoki shubhali holat surati (kip/hodisa bilan
    bog'lanmagan — masalan eski/orfan fayl — bo'lsa operatorga berilmaydi)."""
    if foydalanuvchi.rol != Rol.operator:
        return True

    kip_smenasi = db.scalar(select(Kip.smena).where(Kip.surat_yoli == nisbiy_yol))
    if kip_smenasi is not None:
        return kip_smenasi == foydalanuvchi.smena

    hodisa_smenasi = db.scalar(select(ShubhaliHolat.smena).where(ShubhaliHolat.surat_yoli == nisbiy_yol))
    if hodisa_smenasi is not None:
        return hodisa_smenasi == foydalanuvchi.smena

    return False


@router.get("/kip-surat/{fayl_yoli:path}")
def kip_surati(
    fayl_yoli: str,
    db: Session = Depends(get_db),
    foydalanuvchi: Foydalanuvchi = Depends(joriy_foydalanuvchi),
) -> FileResponse:
    """Kip (yoki shubhali holat) surati — `services/media.py:surat_ommaviy_url()`
    shu endpointga ishora qiladigan URL yasaydi."""
    fayl = _xavfsiz_fayl(fayl_yoli)
    if not _surat_royxati_ruxsat(db, foydalanuvchi, fayl_yoli):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Bu surat sizniki emas")
    return FileResponse(fayl, media_type="image/jpeg")

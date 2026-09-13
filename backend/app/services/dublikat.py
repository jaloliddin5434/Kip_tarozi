"""Bir xil partiyaga bir necha soniya ichida deyarli bir xil og'irlik qayta
kiritilishini aniqlaydi ("bu haqiqatan yangi kipmi?" ogohlantirishi uchun).

Ilgari `app/api/v1/routes/kiplar.py` ichida faqat oddiy (kamera ishlayotgan)
saqlash oqimida ishlatilgan; endi "kamera ishlamasa — Admin tasdig'i" oqimida
ham (`app/services/kamera_tasdiq.py`) ishlatilishi uchun umumiy joyga
ko'chirildi.
"""

from datetime import datetime

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.kip import Kip, KipHolati


def topish(db: Session, partiya_id: int, ogirlik: float, hozir: datetime) -> Kip | None:
    """Shu partiyada ENG SO'NGGI aktiv kip vaqt+og'irlik bo'yicha yaqin
    (`DUPLIKAT_VAQT_OYNASI_SONIYA`/`DUPLIKAT_OGIRLIK_TOLERANSI_KG`) bo'lsa —
    o'shani, aks holda `None` qaytaradi."""
    songi = db.scalar(
        select(Kip)
        .where(Kip.partiya_id == partiya_id, Kip.holati == KipHolati.aktiv)
        .order_by(Kip.vaqt.desc())
        .limit(1)
    )
    if songi is None:
        return None
    if (hozir - songi.vaqt).total_seconds() > settings.DUPLIKAT_VAQT_OYNASI_SONIYA:
        return None
    if abs(float(songi.ogirlik) - ogirlik) > settings.DUPLIKAT_OGIRLIK_TOLERANSI_KG:
        return None
    return songi

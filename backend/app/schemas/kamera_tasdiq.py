from datetime import datetime

from pydantic import BaseModel

from app.models.foydalanuvchi import Smena
from app.models.kamera_tasdiq import KameraTasdiqHolati


class KameraTasdiqKutilmoqda(BaseModel):
    """`POST /kiplar` javobi (HTTP 202) — kamera surat ololmadi, operator Admin
    ruxsatini kutishi kerak. Frontend `kamera_tasdiq_kutilmoqda == true` bo'yicha
    oddiy kip javobidan farqlaydi."""

    kamera_tasdiq_kutilmoqda: bool = True
    sorov_id: int
    holati: KameraTasdiqHolati = KameraTasdiqHolati.kutilmoqda


class KameraTasdiqHolatJavob(BaseModel):
    """Operator polling qiladi (`GET /kamera-tasdiq/{id}/holat`,
    `GET /kamera-tasdiq/mening-kutilayotganim`). `vaqt` — so'rov QACHON
    yaratilgani (bloklovchi dialogdagi "necha vaqtdan beri kutilmoqda"
    hisoblagichi uchun kerak — operator ilovani qayta ochsa ham, hisoblagich
    haqiqiy boshlanish vaqtidan davom etsin)."""

    id: int
    vaqt: datetime
    holati: KameraTasdiqHolati
    kip_id: int | None = None
    izoh: str | None = None


class KameraTasdiqRoyxatJavob(BaseModel):
    id: int
    vaqt: datetime
    smena: Smena
    ogirlik: float
    mahsulot_nomi: str
    partiya_raqami: int
    operator_ism: str
    holati: KameraTasdiqHolati
    kip_id: int | None
    hal_qilingan_vaqt: datetime | None
    hal_qilgan_ism: str | None
    hal_qilish_manbasi: str | None
    izoh: str | None


class KameraTasdiqRadEtish(BaseModel):
    izoh: str | None = None

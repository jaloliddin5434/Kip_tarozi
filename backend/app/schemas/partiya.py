from datetime import date, datetime

from pydantic import BaseModel

from app.models.partiya import PartiyaHolati


class PartiyaOchish(BaseModel):
    mahsulot_kodi: str
    partiya_raqami: int


class PartiyaOlchov(BaseModel):
    """Faqat sort/og'irlik o'lchovlari — Tayyor mahsulotlar bo'limi ham
    to'ldira oladi. Xaridor/dogovor/narx kabi shartnoma maydonlari bu yerda
    yo'q — ularni faqat Admin PartiyaSotish orqali kiritadi."""

    sort: str | None = None
    urama_bilan_vazn: float
    urama_vazni: float
    sof_vazn: float
    kondicion_vazni: float | None = None


class PartiyaSotish(BaseModel):
    sotuv_sanasi: date
    xaridor: str
    dogovor_raqami: str | None = None
    sort: str | None = None
    urama_bilan_vazn: float
    urama_vazni: float
    sof_vazn: float
    kondicion_vazni: float | None = None
    sotuv_narxi: float | None = None


class PartiyaJavob(BaseModel):
    id: int
    mahsulot_id: int
    mahsulot_kodi: str
    mahsulot_nomi: str
    partiya_raqami: int
    holati: PartiyaHolati
    yaratilgan_vaqt: datetime
    yopilgan_vaqt: datetime | None
    kip_soni: int
    jami_kg: float

    # Sotuv ma'lumotlari (faqat "sotilgan" holatda to'ldirilgan)
    sotuv_sanasi: date | None = None
    xaridor: str | None = None
    dogovor_raqami: str | None = None
    sort: str | None = None
    urama_bilan_vazn: float | None = None
    urama_vazni: float | None = None
    sof_vazn: float | None = None
    kondicion_vazni: float | None = None
    sotuv_narxi: float | None = None
    nakladnoy_raqami: str | None = None
    nakladnoy_pdf_yoli: str | None = None

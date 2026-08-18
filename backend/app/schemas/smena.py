from datetime import datetime

from pydantic import BaseModel


class MahsulotBoyichaHolat(BaseModel):
    mahsulot_kodi: str
    mahsulot_nomi: str
    soni: int
    jami_kg: float


class SmenaHolati(BaseModel):
    smena: str
    sana: str
    mahsulotlar: list[MahsulotBoyichaHolat]


class SmenaKipYozuvi(BaseModel):
    id: int
    kip_raqami: int
    ogirlik: float
    vaqt: datetime
    holati: str

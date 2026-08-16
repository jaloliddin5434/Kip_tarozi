from datetime import datetime

from pydantic import BaseModel

from app.models.partiya import PartiyaHolati


class PartiyaOchish(BaseModel):
    mahsulot_kodi: str
    partiya_raqami: int


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

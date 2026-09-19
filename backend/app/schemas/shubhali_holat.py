from datetime import datetime

from pydantic import BaseModel, ConfigDict

from app.models.foydalanuvchi import Smena
from app.models.shubhali_holat import ShubhaliHolatStatusi


class ShubhaliHolatJavob(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    vaqt: datetime
    smena: Smena | None
    ogirlik: float
    surat_yoli: str | None
    holati: ShubhaliHolatStatusi
    korib_chiqqan_id: int | None
    korib_chiqilgan_vaqt: datetime | None
    stansiya_id: int | None = None


class ShubhaliHolatRoyxatJavob(ShubhaliHolatJavob):
    korib_chiqqan_ism: str | None = None
    operator_ism: str | None = None
    tasdiqlangan: bool


class ShubhaliHolatKipSifatidaSaqlash(BaseModel):
    """`POST /shubhali-holatlar/{id}/saqlash` so'rov tanasi — admin hodisani
    HAQIQIY Kip sifatida saqlash uchun mahsulot/partiyani qo'lda tanlaydi
    (kip-to'g'irlash zayavkasi yaratishdagi bilan bir xil naqsh)."""

    mahsulot_kodi: str
    partiya_raqami: int


class ShubhaliOperatorSoni(BaseModel):
    operator_id: int
    ism: str
    soni: int


class ShubhaliHolatStatistika(BaseModel):
    smena_boyicha: dict[str, int]
    operator_boyicha: list[ShubhaliOperatorSoni]

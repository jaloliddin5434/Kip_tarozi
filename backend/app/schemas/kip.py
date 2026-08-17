from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict

from app.models.foydalanuvchi import Smena
from app.models.kip import KipHolati
from app.schemas.hujjat import AuditLogJavob


class KipYaratish(BaseModel):
    mijoz_id: str
    partiya_id: int
    ogirlik: float
    mahalliy_vaqt: datetime
    surat_yoli: str | None = None
    majburiy: bool = False
    stansiya_id: int | None = None


class KipTahrirlash(BaseModel):
    ogirlik: float | None = None
    sabab: str


class KipJavob(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    mijoz_id: str
    partiya_id: int
    kip_raqami: int
    ogirlik: float
    smena: Smena
    operator_id: int
    mahalliy_vaqt: datetime
    vaqt: datetime
    sinxronlangan: bool
    surat_yoli: str | None
    holati: KipHolati
    stansiya_id: int | None


class KipBatafsilJavob(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    mijoz_id: str
    partiya_id: int
    partiya_raqami: int
    mahsulot_kodi: str
    mahsulot_nomi: str
    kip_raqami: int
    ogirlik: float
    smena: Smena
    operator_id: int
    operator_ism: str
    mahalliy_vaqt: datetime
    vaqt: datetime
    sinxronlangan: bool
    surat_yoli: str | None
    holati: KipHolati
    stansiya_id: int | None
    audit_log: list[AuditLogJavob]


class KipSinxronNatija(BaseModel):
    mijoz_id: str
    holat: Literal["saqlandi", "allaqachon_mavjud", "xato"]
    kip_id: int | None = None
    xabar: str | None = None

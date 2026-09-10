from datetime import datetime

from pydantic import BaseModel

from app.models.kip_togrilash import KipTogrilashHolati


class KipTogrilashYaratish(BaseModel):
    kip_id: int
    yangi_mahsulot_kodi: str
    yangi_partiya_raqami: int
    sabab: str


class KipTogrilashHolatJavob(BaseModel):
    id: int
    holati: KipTogrilashHolati
    izoh: str | None = None


class KipTogrilashRoyxatJavob(BaseModel):
    id: int
    vaqt: datetime
    kip_id: int
    kip_raqami: int
    operator_ism: str
    eski_mahsulot_nomi: str
    eski_partiya_raqami: int
    yangi_mahsulot_nomi: str
    yangi_partiya_raqami: int
    sabab: str
    holati: KipTogrilashHolati
    hal_qilingan_vaqt: datetime | None
    hal_qilgan_ism: str | None
    hal_qilish_manbasi: str | None
    izoh: str | None


class KipTogrilashRadEtish(BaseModel):
    izoh: str | None = None

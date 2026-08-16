from datetime import datetime

from pydantic import BaseModel, ConfigDict

from app.models.audit_log import AuditAmal
from app.models.foydalanuvchi import Smena
from app.models.kip import KipHolati


class HujjatKipJavob(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    mahsulot_kodi: str
    mahsulot_nomi: str
    partiya_id: int
    partiya_raqami: int
    kip_raqami: int
    ogirlik: float
    smena: Smena
    operator_id: int
    operator_ism: str
    vaqt: datetime
    surat_yoli: str | None
    holati: KipHolati


class AuditLogJavob(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    foydalanuvchi_id: int
    foydalanuvchi_ism: str
    jadval_nomi: str
    yozuv_id: int
    amal: AuditAmal
    eski_qiymat: dict | None
    yangi_qiymat: dict | None
    sabab: str
    vaqt: datetime

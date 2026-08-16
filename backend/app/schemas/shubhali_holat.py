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

from datetime import datetime

from pydantic import BaseModel

from app.schemas.statistika import MahsulotJamlanmasi


class AgentHolatJavob(BaseModel):
    ulangan: bool
    oxirgi_xato: str | None
    anti_ogirlik_holati: str
    navbat_uzunligi: int
    yangilangan_vaqt: datetime
    yangimi: bool


class DashboardJavob(BaseModel):
    sana: str
    mahsulotlar: list[MahsulotJamlanmasi]
    jami_soni: int
    jami_kg: float
    ochiq_partiyalar_soni: int
    tasdiqlanmagan_shubhali_holatlar_soni: int
    agent_holati: AgentHolatJavob | None

from datetime import date, datetime

from pydantic import BaseModel

from app.schemas.statistika import MahsulotJamlanmasi, SmenaJamlanmasi


class AgentHolatJavob(BaseModel):
    ulangan: bool
    oxirgi_xato: str | None
    anti_ogirlik_holati: str
    navbat_uzunligi: int
    yangilangan_vaqt: datetime
    yangimi: bool


class DashboardJavob(BaseModel):
    davr: str
    boshlanish_sanasi: date
    tugash_sanasi: date
    mahsulotlar: list[MahsulotJamlanmasi]
    jami_soni: int
    jami_kg: float
    smenalar: list[SmenaJamlanmasi]
    # Davrga bog'liq emas — doim joriy holatni ko'rsatadi
    ochiq_partiyalar_soni: int
    tasdiqlanmagan_shubhali_holatlar_soni: int
    agent_holati: AgentHolatJavob | None

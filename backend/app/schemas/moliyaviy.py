from datetime import date, datetime

from pydantic import BaseModel


class MoliyaviyKirish(BaseModel):
    parol: str


class MoliyaviyToken(BaseModel):
    access_token: str
    token_type: str = "bearer"
    muddat_daqiqa: int


class UzexNarxJavob(BaseModel):
    mahsulot_kodi: str
    mahsulot_nomi: str
    narx_som: float
    yangilangan_vaqt: datetime


class MoliyaviyMahsulotHisoboti(BaseModel):
    mahsulot_kodi: str
    mahsulot_nomi: str
    partiyalar_soni: int
    jami_sof_vazn: float
    jami_summa: float


class MoliyaviyHisobot(BaseModel):
    davr: str
    boshlanish_sanasi: date
    tugash_sanasi: date
    mahsulotlar: list[MoliyaviyMahsulotHisoboti]
    jami_summa: float

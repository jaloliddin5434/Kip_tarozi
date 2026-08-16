from datetime import date

from pydantic import BaseModel


class MahsulotJamlanmasi(BaseModel):
    mahsulot_kodi: str
    mahsulot_nomi: str
    soni: int
    jami_kg: float


class DavrJamlanmasi(BaseModel):
    davr: str
    boshlanish_sanasi: date
    tugash_sanasi: date
    mahsulotlar: list[MahsulotJamlanmasi]
    jami_soni: int
    jami_kg: float


class SmenaJamlanmasi(BaseModel):
    smena: str
    soni: int
    jami_kg: float


class OperatorJamlanmasi(BaseModel):
    operator_id: int
    ism: str
    login: str
    smena: str | None
    soni: int
    jami_kg: float

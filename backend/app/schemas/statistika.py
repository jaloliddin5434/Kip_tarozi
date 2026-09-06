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


class RekordSmena(BaseModel):
    smena: str
    jami_kg: float


class RekordOperator(BaseModel):
    operator_id: int
    ism: str
    login: str
    soni: int


class RekordKun(BaseModel):
    sana: date
    jami_kg: float


class RekordlarJavob(BaseModel):
    """Statistika ekranidagi "Rekord" paneli uchun. eng_yaxshi_smena va
    eng_yaxshi_operator tanlangan `davr` bo'yicha; eng_yuqori_kunlik_yigim
    esa DOIM barcha vaqt bo'yicha (davrga bog'liq emas)."""

    davr: str
    boshlanish_sanasi: date
    tugash_sanasi: date
    eng_yaxshi_smena: RekordSmena | None
    eng_yaxshi_operator: RekordOperator | None
    eng_yuqori_kunlik_yigim: RekordKun | None

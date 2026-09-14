import enum
from datetime import datetime
from typing import Literal

from pydantic import BaseModel


class TasdiqTarixiHolati(str, enum.Enum):
    """`KameraTasdiqHolati` va `KipTogrilashHolati`ning QIYMATLARI bir xil
    (kutilmoqda/tasdiqlangan/rad_etilgan) — shu umumiy filtr uchun mustaqil,
    ikkalasidan bir xil qiymat bilan qurilishi mumkin bo'lgan enum."""

    kutilmoqda = "kutilmoqda"
    tasdiqlangan = "tasdiqlangan"
    rad_etilgan = "rad_etilgan"


class TasdiqTarixiYozuvi(BaseModel):
    """`GET /tasdiqlash-tarixi` — kamera-tasdiq so'rovlari va kip-to'g'rilash
    zayavkalarini BITTA normallashtirilgan qatorga birlashtirgan javob.
    `tur` qaysi asl jadvaldan kelganini bildiradi — frontend amallarni
    (tasdiqlash/rad-etish) shunga qarab tegishli `/kamera-tasdiq` yoki
    `/kip-togrilash` endpointiga yo'naltiradi."""

    tur: Literal["kamera", "kip_togrilash"]
    id: int
    vaqt: datetime
    operator_ism: str
    tavsif: str  # nima haqida: mahsulot/partiya (+kamera uchun og'irlik) yoki eski->yangi
    sabab: str | None  # faqat kip_togrilash'da (operator ko'rsatgan sabab)
    holati: TasdiqTarixiHolati
    hal_qilingan_vaqt: datetime | None
    hal_qilgan_ism: str | None
    hal_qilish_manbasi: str | None
    izoh: str | None  # hal qiluvchining (admin) izohi, faqat rad etishda ixtiyoriy kiritiladi
    # Faqat tur="kamera" va hali "kutilmoqda" qatorlar uchun hisoblanadi (qarang
    # GET /kamera-tasdiq'dagi bir xil naqsh) — kip_togrilash uchun har doim False.
    dublikat_shubhasi: bool = False

import enum
from datetime import datetime

from sqlalchemy import Boolean, DateTime, Enum, ForeignKey, Numeric, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base
from app.models.foydalanuvchi import Smena


class KameraTasdiqHolati(str, enum.Enum):
    kutilmoqda = "kutilmoqda"
    tasdiqlangan = "tasdiqlangan"
    rad_etilgan = "rad_etilgan"


class KameraTasdiqSorovi(Base):
    """Kamera SOZLANGAN, lekin surat OLINMAGAN holatida: kip darhol saqlanmaydi,
    o'rniga shu "kutilayotgan tasdiq" yoziladi va operator to'liq bloklanadi.
    Admin (admin panel yoki — 2-bosqichda — Telegram tugmasi orqali) real vaqtda
    tasdiqlaganda kip SURATSIZ avtomatik saqlanadi; rad etsa — operator blokdan
    chiqadi va qaytadan urinadi.

    Faqat ONLAYN `POST /kiplar` yo'liga tegishli — offline navbat / Agent
    sinxroni (`POST /kiplar/sinxron`) bu oqimdan o'tmaydi (u yerda operator
    allaqachon keyingi ishga o'tgan)."""

    __tablename__ = "kamera_tasdiq_sorovlari"

    id: Mapped[int] = mapped_column(primary_key=True)
    # Operator qurilmasida generatsiya qilingan UUID — qayta yuborishda (tarmoq
    # uzilishi) ikki marta so'rov yaratilmasligi (idempotentlik) uchun.
    mijoz_id: Mapped[str] = mapped_column(String(36), unique=True)

    partiya_id: Mapped[int] = mapped_column(ForeignKey("partiyalar.id"))
    ogirlik: Mapped[float] = mapped_column(Numeric(6, 2))
    smena: Mapped[Smena] = mapped_column(Enum(Smena, name="smena_turi"))
    operator_id: Mapped[int] = mapped_column(ForeignKey("foydalanuvchilar.id"))
    stansiya_id: Mapped[int | None] = mapped_column(ForeignKey("stansiyalar.id"), nullable=True)
    mahalliy_vaqt: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    # Operator "majburiy" (dublikat ogohlantirishini bosib o'tib) saqlagan bo'lsa —
    # tasdiqlanganda kip ham shu bayroq bilan yoziladi.
    majburiy: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")

    vaqt: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    holati: Mapped[KameraTasdiqHolati] = mapped_column(
        Enum(KameraTasdiqHolati, name="kamera_tasdiq_holati_turi"),
        default=KameraTasdiqHolati.kutilmoqda,
        server_default=KameraTasdiqHolati.kutilmoqda.value,
    )
    # Tasdiqlangach yaratilgan kip
    kip_id: Mapped[int | None] = mapped_column(ForeignKey("kiplar.id"), nullable=True)

    hal_qilgan_id: Mapped[int | None] = mapped_column(ForeignKey("foydalanuvchilar.id"), nullable=True)
    hal_qilingan_vaqt: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    # "panel" yoki "telegram" (2-bosqich) — kim/qayerdan hal qilgani
    hal_qilish_manbasi: Mapped[str | None] = mapped_column(String(50), nullable=True)
    izoh: Mapped[str | None] = mapped_column(Text, nullable=True)

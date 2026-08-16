import enum
from datetime import datetime

from sqlalchemy import Boolean, DateTime, Enum, ForeignKey, Integer, Numeric, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base
from app.models.foydalanuvchi import Smena


class KipHolati(str, enum.Enum):
    aktiv = "aktiv"
    bekor_qilingan = "bekor_qilingan"
    tahrirlangan = "tahrirlangan"


class Kip(Base):
    """Bitta tortilgan yuk (paket). kip_raqami partiya ichida 1 dan avtomatik ortadi.
    mijoz_id — operator qurilmasida (Stansiya Agenti) generatsiya qilingan UUID;
    offline navbatdan qayta yuborilganda yoki tarmoq xatosidan keyin qayta
    urinilganda ikki marta yozilib qolmasligi (dublikat) uchun ishlatiladi.
    mahalliy_vaqt — offline holatda operator qurilmasida yozilgan asl vaqt;
    vaqt — serverga sinxronlanganda tasdiqlangan vaqt (odatda mahalliy_vaqt bilan bir xil,
    faqat offline navbatdan kech yetib kelganda farqlanishi mumkin)."""

    __tablename__ = "kiplar"
    __table_args__ = (UniqueConstraint("partiya_id", "kip_raqami", name="uq_kip_partiya_raqam"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    mijoz_id: Mapped[str] = mapped_column(String(36), unique=True)
    partiya_id: Mapped[int] = mapped_column(ForeignKey("partiyalar.id"))
    kip_raqami: Mapped[int] = mapped_column(Integer)

    ogirlik: Mapped[float] = mapped_column(Numeric(6, 2))
    smena: Mapped[Smena] = mapped_column(Enum(Smena, name="smena_turi"))
    operator_id: Mapped[int] = mapped_column(ForeignKey("foydalanuvchilar.id"))
    stansiya_id: Mapped[int | None] = mapped_column(ForeignKey("stansiyalar.id"), nullable=True)

    mahalliy_vaqt: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    vaqt: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    sinxronlangan: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")

    surat_yoli: Mapped[str | None] = mapped_column(String(500), nullable=True)
    holati: Mapped[KipHolati] = mapped_column(Enum(KipHolati, name="kip_holati_turi"), default=KipHolati.aktiv)

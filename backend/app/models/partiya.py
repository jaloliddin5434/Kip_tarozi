import enum
from datetime import date, datetime

from sqlalchemy import Date, DateTime, Enum, ForeignKey, Integer, Numeric, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class PartiyaHolati(str, enum.Enum):
    ochiq = "ochiq"
    yopiq = "yopiq"
    sotilgan = "sotilgan"


class Partiya(Base):
    """Bitta mahsulot turi ichida ketma-ket raqamlanadi (partiya_raqami mahsulot
    ichida mustaqil). Sotuv maydonlari faqat 'sotilgan' holatga o'tganda to'ldiriladi."""

    __tablename__ = "partiyalar"
    __table_args__ = (UniqueConstraint("mahsulot_id", "partiya_raqami", name="uq_partiya_mahsulot_raqam"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    mahsulot_id: Mapped[int] = mapped_column(ForeignKey("mahsulotlar.id"))
    partiya_raqami: Mapped[int] = mapped_column(Integer)

    holati: Mapped[PartiyaHolati] = mapped_column(
        Enum(PartiyaHolati, name="partiya_holati_turi"), default=PartiyaHolati.ochiq
    )

    yaratgan_id: Mapped[int | None] = mapped_column(ForeignKey("foydalanuvchilar.id"), nullable=True)
    yopgan_id: Mapped[int | None] = mapped_column(ForeignKey("foydalanuvchilar.id"), nullable=True)

    yaratilgan_vaqt: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    yopilgan_vaqt: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    # --- Sotuv ma'lumotlari (faqat sotilganda to'ldiriladi) ---
    sotuv_sanasi: Mapped[date | None] = mapped_column(Date, nullable=True)
    xaridor: Mapped[str | None] = mapped_column(String(200), nullable=True)
    dogovor_raqami: Mapped[str | None] = mapped_column(String(100), nullable=True)
    sort: Mapped[str | None] = mapped_column(String(50), nullable=True)
    urama_bilan_vazn: Mapped[float | None] = mapped_column(Numeric(10, 2), nullable=True)
    urama_vazni: Mapped[float | None] = mapped_column(Numeric(10, 2), nullable=True)
    sof_vazn: Mapped[float | None] = mapped_column(Numeric(10, 2), nullable=True)
    kondicion_vazni: Mapped[float | None] = mapped_column(Numeric(10, 2), nullable=True)
    sotuv_narxi: Mapped[float | None] = mapped_column(Numeric(14, 2), nullable=True)

    nakladnoy_raqami: Mapped[str | None] = mapped_column(String(50), nullable=True)
    nakladnoy_pdf_yoli: Mapped[str | None] = mapped_column(String(500), nullable=True)

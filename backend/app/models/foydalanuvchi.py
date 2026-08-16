import enum
from datetime import datetime

from sqlalchemy import Boolean, DateTime, Enum, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class Rol(str, enum.Enum):
    admin = "admin"
    operator = "operator"
    tayyor_mahsulotlar = "tayyor_mahsulotlar"


class Smena(str, enum.Enum):
    A = "A"
    B = "B"
    C = "C"
    D = "D"


class Foydalanuvchi(Base):
    """Tizim foydalanuvchisi. Operator uchun login smenaga umumiy (A/B/C/D),
    Admin va Tayyor mahsulotlar bo'limi uchun shaxsiy."""

    __tablename__ = "foydalanuvchilar"

    id: Mapped[int] = mapped_column(primary_key=True)
    ism: Mapped[str] = mapped_column(String(100))
    login: Mapped[str] = mapped_column(String(50), unique=True, index=True)
    parol_hash: Mapped[str] = mapped_column(String(255))
    rol: Mapped[Rol] = mapped_column(Enum(Rol, name="rol_turi"))
    smena: Mapped[Smena | None] = mapped_column(Enum(Smena, name="smena_turi"), nullable=True)
    faol: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")

    xato_urinishlar: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    bloklangan_gacha: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    oxirgi_kirish: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    yaratilgan_vaqt: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

from sqlalchemy import Boolean, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class Stansiya(Base):
    """Tortish stansiyasi (tarozi + kamera juftligi). Hozircha bitta, lekin
    kelajakda qo'shimcha stansiyalar qo'shilishi mumkinligi uchun alohida jadval."""

    __tablename__ = "stansiyalar"

    id: Mapped[int] = mapped_column(primary_key=True)
    nomi: Mapped[str] = mapped_column(String(100))
    rs232_port: Mapped[str] = mapped_column(String(20))
    rs232_baudrate: Mapped[int] = mapped_column(Integer, default=9600)
    kamera_manzili: Mapped[str | None] = mapped_column(String(255), nullable=True)
    faol: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")

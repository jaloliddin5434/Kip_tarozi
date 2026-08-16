from sqlalchemy import Boolean, String
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class Mahsulot(Base):
    """Fixed ro'yxat: Tola, Lint, Pux, Ulyuk. Kod orqali dasturda ishlatiladi,
    nomi admin panelda ko'rsatiladi."""

    __tablename__ = "mahsulotlar"

    id: Mapped[int] = mapped_column(primary_key=True)
    kod: Mapped[str] = mapped_column(String(20), unique=True)
    nomi: Mapped[str] = mapped_column(String(50))
    faol: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")

from datetime import datetime

from sqlalchemy import DateTime, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class Sozlama(Base):
    """Key-value sozlamalar (Telegram token, kamera manzili, moliyaviy bo'lim
    qo'shimcha paroli va h.k.) — admin panelidan o'zgartiriladi, .env emas."""

    __tablename__ = "sozlamalar"

    kalit: Mapped[str] = mapped_column(String(100), primary_key=True)
    qiymat: Mapped[str] = mapped_column(Text)
    tavsif: Mapped[str | None] = mapped_column(String(255), nullable=True)
    yangilangan_vaqt: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

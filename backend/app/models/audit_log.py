import enum
from datetime import datetime

from sqlalchemy import DateTime, Enum, ForeignKey, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class AuditAmal(str, enum.Enum):
    yaratildi = "yaratildi"
    tahrirlandi = "tahrirlandi"
    ochirildi = "ochirildi"


class AuditLog(Base):
    """Har qanday tahrirlash/o'chirish amali shu yerga yoziladi (faqat Admin,
    sabab majburiy). eski_qiymat/yangi_qiymat — o'zgargan maydonlar JSON ko'rinishida."""

    __tablename__ = "audit_log"

    id: Mapped[int] = mapped_column(primary_key=True)
    foydalanuvchi_id: Mapped[int] = mapped_column(ForeignKey("foydalanuvchilar.id"))
    jadval_nomi: Mapped[str] = mapped_column(String(50))
    yozuv_id: Mapped[int] = mapped_column(Integer)
    amal: Mapped[AuditAmal] = mapped_column(Enum(AuditAmal, name="audit_amal_turi"))
    eski_qiymat: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    yangi_qiymat: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    sabab: Mapped[str] = mapped_column(Text)
    vaqt: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

import enum
from datetime import datetime

from sqlalchemy import DateTime, Enum, ForeignKey, Numeric, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base
from app.models.foydalanuvchi import Smena


class ShubhaliHolatStatusi(str, enum.Enum):
    yangi = "yangi"
    korib_chiqildi = "korib_chiqildi"


class ShubhaliHolat(Base):
    """'Yuk saqlanmadi' hodisasi: og'irlik ANTI_OGIRLIK_THRESHOLD_KG dan yuqori
    barqaror turib, Saqlash bosilmasdan pastga tushib ketganda yoziladi.
    Operator 'Tushundim' bosmaguncha (korib_chiqildi) keyingi kipni torta olmaydi."""

    __tablename__ = "shubhali_holatlar"

    id: Mapped[int] = mapped_column(primary_key=True)
    vaqt: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    smena: Mapped[Smena | None] = mapped_column(Enum(Smena, name="smena_turi"), nullable=True)
    operator_id: Mapped[int | None] = mapped_column(ForeignKey("foydalanuvchilar.id"), nullable=True)
    stansiya_id: Mapped[int | None] = mapped_column(ForeignKey("stansiyalar.id"), nullable=True)
    ogirlik: Mapped[float] = mapped_column(Numeric(6, 2))
    surat_yoli: Mapped[str | None] = mapped_column(String(500), nullable=True)

    holati: Mapped[ShubhaliHolatStatusi] = mapped_column(
        Enum(ShubhaliHolatStatusi, name="shubhali_holat_statusi_turi"), default=ShubhaliHolatStatusi.yangi
    )
    korib_chiqqan_id: Mapped[int | None] = mapped_column(ForeignKey("foydalanuvchilar.id"), nullable=True)
    korib_chiqilgan_vaqt: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    izoh: Mapped[str | None] = mapped_column(Text, nullable=True)

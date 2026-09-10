import enum
from datetime import datetime

from sqlalchemy import DateTime, Enum, ForeignKey, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class KipTogrilashHolati(str, enum.Enum):
    kutilmoqda = "kutilmoqda"
    tasdiqlangan = "tasdiqlangan"
    rad_etilgan = "rad_etilgan"


class KipTogrilashZayavkasi(Base):
    """Operator "Smena tarixi" ro'yxatidagi o'z (yoki o'z smenasidagi) bir
    kipi uchun mahsulot/partiya noto'g'ri tanlanganini bildirib, TO'G'RILASH
    so'raydi. Admin (panel yoki Telegram tugmasi orqali) tasdiqlaganda
    `app.services.kip_tahrirlash.kipni_tahrir_qil()` chaqiriladi — xuddi
    admin PATCH /kiplar/{id} bilan tahrirlagandek (surat fayli ham, mahsulot
    haqiqatan o'zgarsa, to'g'ri yangi papkaga ko'chadi)."""

    __tablename__ = "kip_togrilash_zayavkalari"

    id: Mapped[int] = mapped_column(primary_key=True)

    kip_id: Mapped[int] = mapped_column(ForeignKey("kiplar.id"))
    operator_id: Mapped[int] = mapped_column(ForeignKey("foydalanuvchilar.id"))

    # So'ralgan paytdagi holat — snapshot (audit/ko'rsatish uchun; kip o'zi
    # boshqa zayavka/tahrirlash orqali shu orada o'zgarib ketishi mumkin).
    eski_mahsulot_id: Mapped[int] = mapped_column(ForeignKey("mahsulotlar.id"))
    eski_partiya_id: Mapped[int] = mapped_column(ForeignKey("partiyalar.id"))

    yangi_mahsulot_id: Mapped[int] = mapped_column(ForeignKey("mahsulotlar.id"))
    yangi_partiya_id: Mapped[int] = mapped_column(ForeignKey("partiyalar.id"))

    sabab: Mapped[str] = mapped_column(Text)

    vaqt: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    holati: Mapped[KipTogrilashHolati] = mapped_column(
        Enum(KipTogrilashHolati, name="kip_togrilash_holati_turi"),
        default=KipTogrilashHolati.kutilmoqda,
        server_default=KipTogrilashHolati.kutilmoqda.value,
    )

    hal_qilgan_id: Mapped[int | None] = mapped_column(ForeignKey("foydalanuvchilar.id"), nullable=True)
    hal_qilingan_vaqt: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    # "panel" yoki "telegram" — kim/qayerdan hal qilgani (kamera_tasdiq bilan bir xil)
    hal_qilish_manbasi: Mapped[str | None] = mapped_column(String(50), nullable=True)
    # Admin rad etish sababi (ixtiyoriy — faqat panel orqali to'ldiriladi)
    izoh: Mapped[str | None] = mapped_column(Text, nullable=True)

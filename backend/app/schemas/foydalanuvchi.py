from datetime import datetime

from pydantic import BaseModel, ConfigDict, field_validator

from app.models.foydalanuvchi import Rol, Smena


class FoydalanuvchiJavob(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    ism: str
    login: str
    rol: Rol
    smena: Smena | None
    faol: bool
    oxirgi_kirish: datetime | None


class FoydalanuvchiTahrirlash(BaseModel):
    """Admin foydalanuvchining login va/yoki parolini o'zgartiradi.
    Ikkalasi ham ixtiyoriy, lekin kamida bittasi berilishi kerak (bu
    endpointda tekshiriladi). Bo'sh satr — "o'zgartirilmasin" degani."""

    login: str | None = None
    parol: str | None = None

    @field_validator("login")
    @classmethod
    def _loginni_tozalash(cls, v: str | None) -> str | None:
        if v is None:
            return None
        v = v.strip()
        return v or None

    @field_validator("parol")
    @classmethod
    def _bosh_parol_none(cls, v: str | None) -> str | None:
        return v or None


class FoydalanuvchiTokenBekorQilish(BaseModel):
    """Favqulodda holat uchun (masalan operator kompyuteri o'g'irlangan) —
    parolni o'zgartirmasdan, shu hisobning BARCHA amaldagi tokenlarini
    darhol bekor qiladi. `sabab` ixtiyoriy — berilmasa standart matn
    audit_log'ga yoziladi."""

    sabab: str | None = None

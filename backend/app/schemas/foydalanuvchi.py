from datetime import datetime

from pydantic import BaseModel, ConfigDict

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

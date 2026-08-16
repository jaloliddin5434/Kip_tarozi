from pydantic import BaseModel

from app.models.foydalanuvchi import Rol, Smena


class LoginSorov(BaseModel):
    login: str
    parol: str


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"


class TokenMalumot(BaseModel):
    foydalanuvchi_id: int
    rol: Rol
    smena: Smena | None = None

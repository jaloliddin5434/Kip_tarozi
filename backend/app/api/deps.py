from collections.abc import Callable

import jwt
from fastapi import Depends, Header, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import get_db
from app.core.security import tokenni_ochish
from app.models.foydalanuvchi import Foydalanuvchi, Rol

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="api/v1/auth/login")


def joriy_foydalanuvchi(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> Foydalanuvchi:
    xato = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Token yaroqsiz yoki muddati o'tgan",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        malumot = tokenni_ochish(token)
        foydalanuvchi_id = malumot.get("sub")
        if foydalanuvchi_id is None:
            raise xato
    except jwt.PyJWTError:
        raise xato

    foydalanuvchi = db.get(Foydalanuvchi, int(foydalanuvchi_id))
    if foydalanuvchi is None or not foydalanuvchi.faol:
        raise xato
    return foydalanuvchi


def rollarga_ruxsat(*ruxsat_etilgan: Rol) -> Callable[[Foydalanuvchi], Foydalanuvchi]:
    """Masalan: Depends(rollarga_ruxsat(Rol.admin)) — faqat adminga ruxsat."""

    def tekshir(foydalanuvchi: Foydalanuvchi = Depends(joriy_foydalanuvchi)) -> Foydalanuvchi:
        if foydalanuvchi.rol not in ruxsat_etilgan:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Bu amal uchun ruxsat yo'q")
        return foydalanuvchi

    return tekshir


def agent_autentifikatsiya(x_agent_key: str = Header(...)) -> None:
    """Stansiya Agenti backendga (masalan shubhali holat hodisasini) murojaat
    qilganda foydalanuvchi tokeni emas, shu doimiy kalit orqali taniladi."""
    if x_agent_key != settings.AGENT_API_KEY:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Agent kaliti noto'g'ri")

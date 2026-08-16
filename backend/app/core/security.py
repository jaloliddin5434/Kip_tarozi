from datetime import datetime, timedelta, timezone
from typing import Any

import jwt
from passlib.context import CryptContext

from app.core.config import settings

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def parolni_hash(parol: str) -> str:
    return pwd_context.hash(parol)


def parolni_tekshir(parol: str, parol_hash: str) -> bool:
    return pwd_context.verify(parol, parol_hash)


def token_yarat(claims: dict[str, Any]) -> str:
    muddat = datetime.now(timezone.utc) + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode = {**claims, "exp": muddat}
    return jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def tokenni_ochish(token: str) -> dict[str, Any]:
    return jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])

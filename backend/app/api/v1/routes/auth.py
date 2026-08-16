from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import joriy_foydalanuvchi
from app.core.config import settings
from app.core.database import get_db
from app.core.security import parolni_tekshir, token_yarat
from app.models.foydalanuvchi import Foydalanuvchi
from app.schemas.foydalanuvchi import FoydalanuvchiJavob
from app.schemas.token import LoginSorov, Token

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/login", response_model=Token)
def login(malumot: LoginSorov, db: Session = Depends(get_db)) -> Token:
    foydalanuvchi = db.scalar(select(Foydalanuvchi).where(Foydalanuvchi.login == malumot.login))

    xato_javob = HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Login yoki parol noto'g'ri")

    if foydalanuvchi is None or not foydalanuvchi.faol:
        raise xato_javob

    hozir = datetime.now(timezone.utc)
    if foydalanuvchi.bloklangan_gacha and foydalanuvchi.bloklangan_gacha > hozir:
        qoldi = int((foydalanuvchi.bloklangan_gacha - hozir).total_seconds() // 60) + 1
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=f"Ko'p marta xato urinish tufayli akkaunt bloklangan. {qoldi} daqiqadan so'ng qayta urinib ko'ring.",
        )

    if not parolni_tekshir(malumot.parol, foydalanuvchi.parol_hash):
        foydalanuvchi.xato_urinishlar += 1
        if foydalanuvchi.xato_urinishlar >= settings.LOGIN_MAX_ATTEMPTS:
            foydalanuvchi.bloklangan_gacha = hozir + timedelta(minutes=settings.LOGIN_LOCKOUT_MINUTES)
            foydalanuvchi.xato_urinishlar = 0
        db.commit()
        raise xato_javob

    foydalanuvchi.xato_urinishlar = 0
    foydalanuvchi.bloklangan_gacha = None
    foydalanuvchi.oxirgi_kirish = hozir
    db.commit()

    token = token_yarat(
        {
            "sub": str(foydalanuvchi.id),
            "rol": foydalanuvchi.rol.value,
            "smena": foydalanuvchi.smena.value if foydalanuvchi.smena else None,
        }
    )
    return Token(access_token=token)


@router.get("/men", response_model=FoydalanuvchiJavob)
def men(foydalanuvchi: Foydalanuvchi = Depends(joriy_foydalanuvchi)) -> Foydalanuvchi:
    return foydalanuvchi

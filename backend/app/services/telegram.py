import logging

import httpx
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.sozlama import Sozlama

logger = logging.getLogger("telegram")

XATOLIK_TOKEN_KALITI = "telegram_xatolik_bot_token"
XATOLIK_CHAT_KALITI = "telegram_xatolik_chat_id"
STATISTIKA_TOKEN_KALITI = "telegram_statistika_bot_token"
STATISTIKA_CHAT_KALITI = "telegram_statistika_chat_id"


def _sozlama_ol(db: Session, kalit: str) -> str | None:
    sozlama = db.scalar(select(Sozlama).where(Sozlama.kalit == kalit))
    return sozlama.qiymat if sozlama and sozlama.qiymat else None


def _yubor(token: str | None, chat_id: str | None, matn: str) -> None:
    if not token or not chat_id:
        logger.warning("[TELEGRAM] Token/chat_id Sozlamalarda kiritilmagan, xabar yuborilmadi: %s", matn)
        return
    try:
        javob = httpx.post(
            f"https://api.telegram.org/bot{token}/sendMessage",
            json={"chat_id": chat_id, "text": matn},
            timeout=10,
        )
        javob.raise_for_status()
    except httpx.HTTPError:
        logger.exception("Telegramga xabar yuborishda xato")


def xatolik_xabari(db: Session, matn: str) -> None:
    """Texnik xatoliklar/ogohlantirishlar (masalan 'yuk saqlanmadi') — Smart Tarozi bot."""
    _yubor(_sozlama_ol(db, XATOLIK_TOKEN_KALITI), _sozlama_ol(db, XATOLIK_CHAT_KALITI), matn)


def statistika_xabari(db: Session, matn: str) -> None:
    """Kunlik/smena statistik hisobotlar — Hazorasp_tekstil statistika guruhi."""
    _yubor(_sozlama_ol(db, STATISTIKA_TOKEN_KALITI), _sozlama_ol(db, STATISTIKA_CHAT_KALITI), matn)

import logging
from pathlib import Path

import httpx
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.sozlama import Sozlama

logger = logging.getLogger("telegram")

XATOLIK_TOKEN_KALITI = "telegram_xatolik_bot_token"
XATOLIK_CHAT_KALITI = "telegram_xatolik_chat_id"
STATISTIKA_TOKEN_KALITI = "telegram_statistika_bot_token"
STATISTIKA_CHAT_KALITI = "telegram_statistika_chat_id"
SURAT_TOKEN_KALITI = "telegram_surat_bot_token"
SURAT_CHAT_KALITI = "telegram_surat_chat_id"


def _sozlama_ol(db: Session, kalit: str) -> str | None:
    sozlama = db.scalar(select(Sozlama).where(Sozlama.kalit == kalit))
    return sozlama.qiymat if sozlama and sozlama.qiymat else None


def _yubor(token: str | None, chat_id: str | None, matn: str, *, reply_markup: dict | None = None) -> None:
    if not token or not chat_id:
        logger.warning("[TELEGRAM] Token/chat_id Sozlamalarda kiritilmagan, xabar yuborilmadi: %s", matn)
        return
    try:
        tana: dict = {"chat_id": chat_id, "text": matn}
        if reply_markup is not None:
            tana["reply_markup"] = reply_markup
        javob = httpx.post(
            f"https://api.telegram.org/bot{token}/sendMessage",
            json=tana,
            timeout=10,
        )
        javob.raise_for_status()
    except httpx.HTTPError:
        logger.exception("Telegramga xabar yuborishda xato")


def xatolik_xabari(db: Session, matn: str) -> None:
    """Texnik xatoliklar/ogohlantirishlar (masalan 'yuk saqlanmadi') — Smart Tarozi bot."""
    _yubor(_sozlama_ol(db, XATOLIK_TOKEN_KALITI), _sozlama_ol(db, XATOLIK_CHAT_KALITI), matn)


def xatolik_xabari_tugma_bilan(db: Session, matn: str, *, callback_prefiks: str, obyekt_id: int) -> None:
    """`xatolik_xabari` bilan bir xil bot/chat, lekin "✅ Tasdiqlash" /
    "❌ Rad etish" inline tugmalari bilan — admin telefonidan to'g'ridan-to'g'ri
    hal qilishi uchun (kamera-tasdiq va kip-to'g'rilash zayavkasi oqimlari
    ishlatadi). `callback_data`: "{callback_prefiks}:{obyekt_id}:tasdiqlash"
    yoki ":rad_etish" — `app.services.telegram_polling` shuni o'qiydi."""
    tugmalar = {
        "inline_keyboard": [
            [
                {"text": "✅ Tasdiqlash", "callback_data": f"{callback_prefiks}:{obyekt_id}:tasdiqlash"},
                {"text": "❌ Rad etish", "callback_data": f"{callback_prefiks}:{obyekt_id}:rad_etish"},
            ]
        ]
    }
    _yubor(_sozlama_ol(db, XATOLIK_TOKEN_KALITI), _sozlama_ol(db, XATOLIK_CHAT_KALITI), matn, reply_markup=tugmalar)


def statistika_xabari(db: Session, matn: str) -> None:
    """Kunlik/smena statistik hisobotlar — Hazorasp_tekstil statistika guruhi."""
    _yubor(_sozlama_ol(db, STATISTIKA_TOKEN_KALITI), _sozlama_ol(db, STATISTIKA_CHAT_KALITI), matn)


def surat_yubor(
    db: Session,
    surat_yoli: str | None,
    mahsulot_nomi: str,
    partiya_raqami: int,
    kip_raqami: int,
    ogirlik: float,
) -> int | None:
    """Kip surati saqlanganda uni alohida "surat boti"ga (sendPhoto) mahsulot,
    partiya, kip raqami va og'irlik yozuvi bilan birga yuboradi. Xatolik_xabari()
    bilan bir xil YUMSHOQ naqsh: kamera/Telegram/fayl xatosi hech qachon tashqariga
    chiqmaydi (jimgina log), operator hech qanday holatda bloklanmaydi.

    Muvaffaqiyatli yuborilsa, Telegram xabarining `message_id`sini qaytaradi
    (chaqiruvchi buni `kip.telegram_surat_xabar_id`ga saqlashi kerak — kip
    keyinroq tahrirlansa, shu xabarning caption'ini yangilash uchun kerak
    bo'ladi). Yuborilmasa/xato bo'lsa — None.
    """
    if not surat_yoli:
        return None
    try:
        token = _sozlama_ol(db, SURAT_TOKEN_KALITI)
        chat_id = _sozlama_ol(db, SURAT_CHAT_KALITI)
        if not token or not chat_id:
            logger.warning("[TELEGRAM] Surat boti Sozlamalarda kiritilmagan — kip surati yuborilmadi")
            return None

        fayl_yoli = Path(settings.STORAGE_PATH) / surat_yoli
        if not fayl_yoli.is_file():
            logger.warning("[TELEGRAM] Kip surati fayli topilmadi: %s", fayl_yoli)
            return None

        matn = (
            f"Mahsulot: {mahsulot_nomi}\n"
            f"Partiya: #{partiya_raqami}\n"
            f"Kip №{kip_raqami}\n"
            f"Og'irlik: {float(ogirlik):.1f} kg"
        )
        with fayl_yoli.open("rb") as f:
            javob = httpx.post(
                f"https://api.telegram.org/bot{token}/sendPhoto",
                data={"chat_id": chat_id, "caption": matn},
                files={"photo": (fayl_yoli.name, f, "image/jpeg")},
                timeout=20,
            )
        javob.raise_for_status()
        return javob.json().get("result", {}).get("message_id")
    except Exception:  # noqa: BLE001 — Telegram/fayl xatosi operatorni bloklamasin
        logger.exception("Kip suratini Telegramga yuborishda xato")
        return None


def surat_xabarini_yangila(
    db: Session,
    xabar_id: int,
    mahsulot_nomi: str,
    partiya_raqami: int,
    kip_raqami: int,
    ogirlik: float,
) -> None:
    """Admin kipni tahrirlab, mahsuloti HAQIQATAN o'zgarsa — shu kipning
    "surat boti"ga avval yuborilgan ESKI xabarining caption'ini (agar
    `telegram_surat_xabar_id` mavjud bo'lsa) editMessageCaption orqali
    YANGI ma'lumot bilan yangilaydi. `surat_yubor()` bilan bir xil YUMSHOQ
    xato boshqaruvi: Telegram xatosi (masalan xabar juda eski, tahrirlab
    bo'lmaydi) hech kimni bloklamaydi — faqat log."""
    try:
        token = _sozlama_ol(db, SURAT_TOKEN_KALITI)
        chat_id = _sozlama_ol(db, SURAT_CHAT_KALITI)
        if not token or not chat_id:
            logger.warning("[TELEGRAM] Surat boti Sozlamalarda kiritilmagan — surat xabari yangilanmadi")
            return

        matn = (
            "🔄 Tuzatildi:\n"
            f"Mahsulot: {mahsulot_nomi}\n"
            f"Partiya: #{partiya_raqami}\n"
            f"Kip №{kip_raqami}\n"
            f"Og'irlik: {float(ogirlik):.1f} kg"
        )
        javob = httpx.post(
            f"https://api.telegram.org/bot{token}/editMessageCaption",
            json={"chat_id": chat_id, "message_id": xabar_id, "caption": matn},
            timeout=10,
        )
        javob.raise_for_status()
    except Exception:  # noqa: BLE001 — Telegram xatosi tahrirlashni bloklamasin
        logger.exception("Kip surat xabarini Telegramda yangilashda xato")

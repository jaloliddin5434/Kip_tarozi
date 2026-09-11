"""Telegram getUpdates long-polling — kiruvchi callback_query (inline tugma
bosilishi) qabul qilish va tegishli oqimga (kamera-tasdiq yoki kip-to'g'rilash
zayavkasi) yo'naltirish. Loyihada BIRINCHI MARTA Telegram'dan kiruvchi
yangilanish qabul qilinadi — `app/services/telegram.py` avval faqat
sendMessage/sendPhoto (chiquvchi) bilan ishlar edi.

APScheduler EMAS (`rejalashtiruvchi.py`dagidek) — u qisqa davriy joblar
uchun mo'ljallangan, long-poll (Telegramga har bir so'rov navbatdagi
yangilanish kelguncha bir necha soniya bloklanadi) uchun mos emas. Shuning
uchun alohida `threading.Thread` + `Event` bilan, xuddi shu modulning
o'zi ichida boshqariladi.
"""

import logging
import threading
from typing import Any

import httpx
from sqlalchemy.engine import Connection
from sqlalchemy.orm import Session

from app.core.database import SessionLocal
from app.models.sozlama import Sozlama
from app.services import advisory_lock, kamera_tasdiq, kip_togrilash
from app.services.kip_tahrirlash import KipTahrirlashTaqiqlangan
from app.services.telegram import XATOLIK_TOKEN_KALITI, _sozlama_ol, surat_xabarini_yangila

logger = logging.getLogger("telegram_polling")

# Ichki — Telegram getUpdates offsetini bazada saqlaydi (xotirada emas), aks
# holda uvicorn --reload har qayta ishga tushganda Telegram hali offset bilan
# tasdiqlanmagan (eski) yangilanishlarni qayta-qayta yuborib turardi.
OFFSET_SOZLAMA_KALITI = "telegram_getupdates_offset"

_UZUN_POLL_SONIYA = 25  # Telegramga: shuncha vaqt yangilanish kutib tur
_SOROV_TIMEOUT_SONIYA = 35  # httpx: uzun-poll + tarmoq zaxirasi
_XATODAN_KEYINGI_KUTISH_SONIYA = 5

# Ko'p-worker himoyasi (audit topilmasi): faqat shu kalitni ushlagan BITTA
# worker/instance haqiqatan pollashni boshlaydi — qarang app/services/advisory_lock.py.
# Qiymatning o'zi ixtiyoriy — faqat shu bazada boshqa advisory lock bilan
# TO'QNASHMASLIGI kifoya (rejalashtiruvchi.py'da ishlatiladigan kalitdan farqli).
LOCK_KALITI = 72710_0001

_thread: threading.Thread | None = None
_toxtatish_signali = threading.Event()
_lock_ulanishi: Connection | None = None


def _offsetni_ol(db: Session) -> int:
    qiymat = _sozlama_ol(db, OFFSET_SOZLAMA_KALITI)
    try:
        return int(qiymat) if qiymat else 0
    except ValueError:
        return 0


def _offsetni_saqla(db: Session, offset: int) -> None:
    sozlama = db.get(Sozlama, OFFSET_SOZLAMA_KALITI)
    if sozlama is None:
        db.add(
            Sozlama(
                kalit=OFFSET_SOZLAMA_KALITI,
                qiymat=str(offset),
                tavsif="Telegram getUpdates offset (ichki qiymat — qo'lda o'zgartirmang)",
            )
        )
    else:
        sozlama.qiymat = str(offset)
    db.commit()


def bitta_tsikl(db: Session) -> list[dict[str, Any]]:
    """getUpdates'ni BITTA marta chaqiradi, offsetni ilgarilatib Sozlama'ga
    saqlaydi, kelgan yangilanishlar ro'yxatini qaytaradi. Bot tokeni
    sozlanmagan bo'lsa — bo'sh ro'yxat (poll qilinmaydi). Sof funksiya —
    testda `httpx.get` mocklanadi, real Telegramga chiqmaydi."""
    token = _sozlama_ol(db, XATOLIK_TOKEN_KALITI)
    if not token:
        return []

    offset = _offsetni_ol(db)
    try:
        javob = httpx.get(
            f"https://api.telegram.org/bot{token}/getUpdates",
            params={"offset": offset, "timeout": _UZUN_POLL_SONIYA, "allowed_updates": ["callback_query"]},
            timeout=_SOROV_TIMEOUT_SONIYA,
        )
        javob.raise_for_status()
    except httpx.HTTPError:
        # Masalan --reload paytida bir lahza ikkita pollovchi ustma-ust tushsa
        # Telegram 409 qaytaradi — keyingi tsiklda o'zi tuzaladi, shu yerda
        # faqat log yoziladi, chaqiruvchi to'xtatilmaydi.
        logger.warning("Telegram getUpdates so'rovida xato", exc_info=True)
        return []

    natija = javob.json()
    yangilanishlar: list[dict[str, Any]] = natija.get("result", [])
    if yangilanishlar:
        yangi_offset = max(y["update_id"] for y in yangilanishlar) + 1
        _offsetni_saqla(db, yangi_offset)
    return yangilanishlar


def _callback_javobi(token: str | None, callback_id: str, matn: str, *, ogohlantirish: bool = False) -> None:
    if not token:
        return
    try:
        javob = httpx.post(
            f"https://api.telegram.org/bot{token}/answerCallbackQuery",
            json={"callback_query_id": callback_id, "text": matn, "show_alert": ogohlantirish},
            timeout=10,
        )
        javob.raise_for_status()
    except httpx.HTTPError:
        logger.exception("Telegram answerCallbackQuery so'rovida xato")


def _xabarni_yangila(token: str | None, xabar: dict[str, Any], qoshimcha_matn: str) -> None:
    """Tugmalarni olib tashlaydi va asl xabar matniga natijani qo'shadi —
    Telegram chatida kim/qachon hal qilinganini ko'rish uchun."""
    if not token:
        return
    chat_id = xabar.get("chat", {}).get("id")
    message_id = xabar.get("message_id")
    asl_matn = xabar.get("text", "")
    if chat_id is None or message_id is None:
        return
    try:
        javob = httpx.post(
            f"https://api.telegram.org/bot{token}/editMessageText",
            json={
                "chat_id": chat_id,
                "message_id": message_id,
                "text": f"{asl_matn}\n\n{qoshimcha_matn}",
                # Bo'sh inline_keyboard — tugmalarni olib tashlaydi (reply_markup
                # berilmasa, Telegram ESKI tugmalarni SAQLAB qoladi, shuning uchun
                # bo'sh ro'yxatni ANIQ yuborish shart — aks holda hal qilingan
                # so'rovni qayta-qayta bosish mumkin bo'lib qolardi).
                "reply_markup": {"inline_keyboard": []},
            },
            timeout=10,
        )
        javob.raise_for_status()
    except httpx.HTTPError:
        logger.exception("Telegram editMessageText so'rovida xato")


def yangilanishni_qayta_ishla(db: Session, yangilanish: dict[str, Any]) -> None:
    """Bitta Telegram Update'ni qayta ishlaydi. `callback_query` bo'lmasa
    (masalan oddiy matnli xabar) — e'tiborsiz qoldiriladi."""
    callback = yangilanish.get("callback_query")
    if callback is None:
        return

    callback_id = callback.get("id")
    data = callback.get("data") or ""
    qismlar = data.split(":")
    token = _sozlama_ol(db, XATOLIK_TOKEN_KALITI)

    if len(qismlar) != 3:
        logger.warning("Noma'lum callback_data formati: %r", data)
        _callback_javobi(token, callback_id, "Noma'lum so'rov", ogohlantirish=True)
        return

    turi, id_matni, amal = qismlar
    try:
        obyekt_id = int(id_matni)
    except ValueError:
        logger.warning("Noma'lum callback_data id: %r", data)
        _callback_javobi(token, callback_id, "Noma'lum so'rov", ogohlantirish=True)
        return

    tasdiqlansinmi = amal == "tasdiqlash"
    telegram_yangilash = None

    if turi == "kamera":
        sorov, _kip = kamera_tasdiq.sorovni_hal_qil(
            db, obyekt_id, tasdiqlansinmi=tasdiqlansinmi, hal_qilgan_id=None, manba="telegram"
        )
        topilgan_holat = sorov.holati.value if sorov is not None else None
    elif turi == "zayavka":
        try:
            zayavka, _kip, telegram_yangilash = kip_togrilash.zayavkani_hal_qil(
                db, obyekt_id, tasdiqlansinmi=tasdiqlansinmi, hal_qilgan_id=None, manba="telegram"
            )
        except KipTahrirlashTaqiqlangan as exc:
            # 1/2-QISM: zayavka yaratilgandan keyin, Telegram tugmasi
            # bosilishidan OLDIN kip bekor qilingan yoki maqsad partiya
            # sotilgan bo'lishi mumkin — bu holda tsiklni yiqitmasdan,
            # foydalanuvchiga sababni ko'rsatib javob beramiz.
            db.rollback()
            _callback_javobi(token, callback_id, str(exc), ogohlantirish=True)
            return
        topilgan_holat = zayavka.holati.value if zayavka is not None else None
    else:
        logger.warning("Noma'lum callback turi: %r", turi)
        _callback_javobi(token, callback_id, "Noma'lum so'rov turi", ogohlantirish=True)
        return

    if topilgan_holat is None:
        _callback_javobi(token, callback_id, "So'rov topilmadi (eskirgan bo'lishi mumkin)", ogohlantirish=True)
        return

    db.commit()
    # Telegram "surat boti" so'rovi COMMIT'dan KEYIN (4-QISM naqshi).
    if telegram_yangilash is not None:
        surat_xabarini_yangila(db, *telegram_yangilash)

    natija_matni = {
        "tasdiqlangan": "✅ Tasdiqlandi",
        "rad_etilgan": "❌ Rad etildi",
        "kutilmoqda": "Hali kutilmoqda",
    }.get(topilgan_holat, topilgan_holat)

    _callback_javobi(token, callback_id, natija_matni)
    xabar = callback.get("message")
    if xabar is not None:
        _xabarni_yangila(token, xabar, natija_matni)


def _tsikl() -> None:
    while not _toxtatish_signali.is_set():
        db = SessionLocal()
        try:
            yangilanishlar = bitta_tsikl(db)
        except Exception:
            logger.exception("Telegram polling tsiklida xato")
            db.close()
            _toxtatish_signali.wait(_XATODAN_KEYINGI_KUTISH_SONIYA)
            continue

        try:
            for yangilanish in yangilanishlar:
                try:
                    yangilanishni_qayta_ishla(db, yangilanish)
                except Exception:
                    logger.exception("Telegram yangilanishini qayta ishlashda xato: %r", yangilanish)
        finally:
            db.close()

        if not yangilanishlar:
            # getUpdates o'zi uzoq-poll bilan bloklaydi (token sozlangan
            # bo'lsa); token yo'q bo'lsa esa darhol qaytadi — bu holda CPU/DB
            # ulanishini band qilmaslik uchun qisqa kutib turamiz.
            _toxtatish_signali.wait(2)


def ishga_tushir() -> None:
    """Ko'p-worker himoyasi: avval advisory lock olishga urinadi — band
    bo'lsa (boshqa worker/instance allaqachon pollamoqda) bu chaqiruv
    HECH NARSA QILMAYDI (faqat log). Shu tufayli `uvicorn --workers N`
    bilan ishga tushirilsa ham Telegram'ga faqat BITTA getUpdates
    pollovchisi ulanadi (409 Conflict va takroriy callback ishlov
    berishning oldi olinadi)."""
    global _thread, _lock_ulanishi
    if _thread is not None and _thread.is_alive():
        return

    if _lock_ulanishi is None:
        _lock_ulanishi = advisory_lock.olishga_urin(LOCK_KALITI, "Telegram polling")
        if _lock_ulanishi is None:
            return

    _toxtatish_signali.clear()
    _thread = threading.Thread(target=_tsikl, name="telegram-polling", daemon=True)
    _thread.start()
    logger.info("Telegram getUpdates polling ishga tushdi")


def toxtat() -> None:
    global _lock_ulanishi
    _toxtatish_signali.set()
    if _thread is not None:
        _thread.join(timeout=5)
    advisory_lock.boshatish(_lock_ulanishi, "Telegram polling")
    _lock_ulanishi = None
    logger.info("Telegram getUpdates polling to'xtatildi")

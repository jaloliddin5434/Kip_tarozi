"""PostgreSQL sessiya darajasidagi advisory lock — bir nechta backend
worker/instance orasida "faqat bitta nusxa haqiqatan ishga tushsin" turdagi
himoyalash uchun.

AUDIT TOPILMASI (tuzatilmoqda): `app/main.py`dagi `lifespan()` Telegram
long-polling (`telegram_polling.py`) va kunlik hisobot rejalashtiruvchisini
(`rejalashtiruvchi.py`) HAR workerda ishga tushiradi. Agar backend
kelajakda bir nechta worker bilan (masalan `uvicorn --workers 4`) ishga
tushirilsa: (1) bir nechta getUpdates pollovchisi Telegram bilan
to'qnashadi (409 Conflict, cheksiz qayta urinish), (2) kunlik hisobot har
workerda alohida yuborilib N marta takrorlanadi.

`pg_try_advisory_lock(kalit)` — DARHOL qaytadi (hech qachon bloklamaydi):
lock band bo'lsa `False`, band bo'lmasa uni OLIB `True` qaytaradi. Bu lock
TRANZAKSIYAGA emas, SESSIYAGA (DB ulanishga) bog'liq — shuning uchun uni
ushlab turish uchun oddiy so'rov-javob ulanishi (masalan `SessionLocal()`,
har chaqiruvda ochilib-yopiladi) ISHLAMAYDI: ulanish yopilishi bilan lock
ham darhol bo'shab ketadi.

MUHIM (SQLAlchemy pool tuzog'i): `engine.connect()` orqali olingan
ulanishda oddiy `.close()` chaqirish HAQIQIY DB seansini TUGATMAYDI — u
faqat ulanishni POOLGA qaytaradi (keyingi so'rov xuddi shu jismoniy
seansni qayta ishlatishi mumkin), demak advisory lock ham "yopilgandan"
keyin ham ushlanib QOLAVERADI (amalda tekshirilgan). Shuning uchun lock
olingan ulanish DARHOL poolning nazoratidan CHIQARILADI
(`connection.detach()`) — shundan keyingina `.close()` HAQIQIY seansni
tugatadi va Postgres advisory lockni avtomatik bo'shatadi. Muvaffaqiyatsiz
urinishda (lock band) ulanish detach QILINMAYDI — oddiy holda poolga
qaytadi, hech narsa isrof bo'lmaydi.
"""

import logging

from sqlalchemy import text
from sqlalchemy.engine import Connection, Engine

from app.core.database import engine as _asosiy_engine

logger = logging.getLogger("advisory_lock")


def olishga_urin(kalit: int, nomi: str, *, db_engine: Engine | None = None) -> Connection | None:
    """`kalit` uchun advisory lockni OLISHGA urinadi (bloklamaydi, darhol
    qaytadi).

    Muvaffaqiyatli bo'lsa — lockni ushlab turadigan OCHIQ `Connection`ni
    qaytaradi (pool nazoratidan CHIQARILGAN — qarang yuqoridagi modul
    izohi). CHAQIRUVCHI buni dastur/worker to'xtaguncha YOPMASLIGI kerak —
    yopilsa (yoki `.close()` chaqirilsa) lock darhol bo'shaydi. Lock band
    bo'lsa (boshqa worker/instance allaqachon ushlab turibdi) — `None`
    qaytaradi, ulanish oddiy holda poolga qaytarilgan bo'ladi.

    `db_engine` — faqat testlar uchun (haqiqiy `app.core.database.engine`
    o'rniga sinov bazasiga ulangan engine berish imkoni)."""
    eng = db_engine if db_engine is not None else _asosiy_engine
    conn = eng.connect().execution_options(isolation_level="AUTOCOMMIT")
    try:
        olindimi = conn.execute(text("SELECT pg_try_advisory_lock(:kalit)"), {"kalit": kalit}).scalar()
    except Exception:
        logger.exception("%s uchun advisory lock so'rovida xato — ehtiyot chorasi sifatida ishga tushirilmaydi", nomi)
        conn.close()
        return None

    if not olindimi:
        conn.close()  # pool nazoratida qolgani uchun — oddiy checkin, isrofsiz
        logger.info(
            "%s uchun advisory lock (kalit=%s) band — boshqa worker/instance allaqachon ishlab turibdi, "
            "shu jarayon BU workerda ISHGA TUSHIRILMAYDI.",
            nomi,
            kalit,
        )
        return None

    # Lock OLINDI — bu ulanish endi doimiy "lock egasi". Pool uni qaytadan
    # boshqa (bu lockka aloqasi bo'lmagan) so'rov uchun qayta ishlatmasin,
    # shu bilan birga keyinchalik `.close()` chaqirilganda HAQIQIY seans
    # tugab, Postgres lockni avtomatik bo'shatishi uchun — pool nazoratidan
    # chiqaramiz.
    conn.connection.detach()
    logger.info("%s uchun advisory lock olindi (kalit=%s) — bu worker javobgar bo'ladi.", nomi, kalit)
    return conn


def boshatish(conn: Connection | None, nomi: str) -> None:
    """Lockni ushlab turgan (detach qilingan) ulanishni yopadi — bu HAQIQIY
    DB seansini tugatadi, Postgres esa seans tugaganda advisory lockni
    avtomatik bo'shatadi. `conn` `None` bo'lsa (lock umuman olinmagan
    bo'lsa) hech narsa qilmaydi."""
    if conn is None:
        return
    try:
        conn.close()
        logger.info("%s advisory locki bo'shatildi.", nomi)
    except Exception:
        logger.exception("%s advisory lock ulanishini yopishda xato", nomi)

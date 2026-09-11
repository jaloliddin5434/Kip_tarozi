import json
import logging
import sqlite3
import threading
from pathlib import Path

from app.core.config import settings

logger = logging.getLogger("navbat")

_lock = threading.Lock()
_conn: sqlite3.Connection | None = None

# 5-QISM (audit topilmasi): avval "xato" natija olgan yozuv CHEKSIZ qayta
# urinilardi (backend har doim bir xil sababda rad etsa — masalan partiya
# o'chirilgan — yozuv abadiy navbatda qolib, har tsiklda qayta yuborilardi).
# Endi `_MAX_URINISH` marta muvaffaqiyatsizlikdan keyin yozuv "muammoli"
# (dead-letter) deb belgilanadi: `hammasini_olish()` uni ENDI qaytarmaydi
# (qayta urinish to'xtaydi), lekin O'CHIRILMAYDI ham (ma'lumot yo'qolmaydi) —
# admin `muammoli_soni()`/`muammolilarni_olish()` orqali ko'rishi mumkin.
_MAX_URINISH = 5
HOLAT_FAOL = "faol"
HOLAT_MUAMMOLI = "muammoli"


def _ulanish() -> sqlite3.Connection:
    global _conn
    # THREAD-XAVFSIZLIK (Task H tekshiruvida topilgan): oldin bu yerda
    # qulfsiz "if _conn is None" tekshiruvi bo'lgan — fon thread
    # (SinxronIshchisi) va asosiy so'rov (masalan /holat) bir vaqtda
    # BIRINCHI ulanishga urinsa, ikkalasi ham `_conn is None`ni ko'rib
    # qolishi mumkin edi: biri jadval yaratishni TUGATMASDAN turib,
    # ikkinchisi allaqachon global `_conn`ni o'qib so'rov yuborsa —
    # "no such table: navbat" xatosi. Endi tez yo'l (odatiy holat, ulanish
    # allaqachon mavjud) qulfsiz tekshiriladi, lekin BIRINCHI ulanish/jadval
    # yaratish "double-checked locking" bilan `_lock` ostida, atomik tarzda
    # bajariladi — faqat bitta thread haqiqatan ulanadi va jadval yaratadi,
    # qolganlari qulfni kutib, tayyor ulanishni qaytarib oladi.
    if _conn is not None:
        return _conn
    with _lock:
        if _conn is None:
            Path(settings.AGENT_QUEUE_DB_PATH).parent.mkdir(parents=True, exist_ok=True)
            yangi_conn = sqlite3.connect(settings.AGENT_QUEUE_DB_PATH, check_same_thread=False)
            yangi_conn.execute(
                f"""CREATE TABLE IF NOT EXISTS navbat (
                    mijoz_id TEXT PRIMARY KEY,
                    token TEXT NOT NULL,
                    payload TEXT NOT NULL,
                    yaratilgan_vaqt TEXT NOT NULL,
                    urinishlar_soni INTEGER NOT NULL DEFAULT 0,
                    oxirgi_xato TEXT,
                    holati TEXT NOT NULL DEFAULT '{HOLAT_FAOL}'
                )"""
            )
            # Eski (ustun qo'shilishidan OLDIN yaratilgan) navbat fayllari
            # uchun — CREATE TABLE IF NOT EXISTS mavjud jadvalga tegmaydi,
            # shuning uchun ustun yo'qligini alohida tekshirib qo'shamiz.
            ustunlar = {qator[1] for qator in yangi_conn.execute("PRAGMA table_info(navbat)").fetchall()}
            if "holati" not in ustunlar:
                yangi_conn.execute(f"ALTER TABLE navbat ADD COLUMN holati TEXT NOT NULL DEFAULT '{HOLAT_FAOL}'")
            yangi_conn.commit()
            _conn = yangi_conn
    return _conn


def qoshish(mijoz_id: str, token: str, payload: dict) -> None:
    conn = _ulanish()
    with _lock:
        conn.execute(
            "INSERT OR IGNORE INTO navbat (mijoz_id, token, payload, yaratilgan_vaqt) "
            "VALUES (?, ?, ?, datetime('now'))",
            (mijoz_id, token, json.dumps(payload)),
        )
        conn.commit()


def hammasini_olish() -> list[dict]:
    """FAQAT 'faol' yozuvlarni qaytaradi — `sinxron.py` shu ro'yxatni
    backendga yuboradi. Dead-letter ('muammoli') qilingan yozuvlar bu yerda
    YO'Q (cheksiz qayta urinish to'xtagan), lekin jadvalda saqlanib qoladi —
    `muammolilarni_olish()` bilan ko'rish mumkin."""
    conn = _ulanish()
    with _lock:
        qatorlar = conn.execute(
            "SELECT mijoz_id, token, payload, urinishlar_soni FROM navbat WHERE holati = ? ORDER BY yaratilgan_vaqt",
            (HOLAT_FAOL,),
        ).fetchall()
    return [{"mijoz_id": r[0], "token": r[1], "payload": json.loads(r[2]), "urinishlar_soni": r[3]} for r in qatorlar]


def ochirish(mijoz_id: str) -> None:
    conn = _ulanish()
    with _lock:
        conn.execute("DELETE FROM navbat WHERE mijoz_id = ?", (mijoz_id,))
        conn.commit()


def xato_belgila(mijoz_id: str, xabar: str) -> None:
    """Urinishlar sonini oshiradi. `_MAX_URINISH`ga yetsa — yozuvni
    'muammoli' (dead-letter) deb belgilaydi va WARNING log yozadi (admin
    buni loglardan yoki `muammoli_soni()`/`muammolilarni_olish()` orqali
    ko'radi) — shu yozuv endi `hammasini_olish()`da qaytmaydi, cheksiz
    qayta urinish shu yerda to'xtaydi."""
    conn = _ulanish()
    with _lock:
        conn.execute(
            """UPDATE navbat
               SET urinishlar_soni = urinishlar_soni + 1,
                   oxirgi_xato = ?,
                   holati = CASE WHEN urinishlar_soni + 1 >= ? THEN ? ELSE holati END
               WHERE mijoz_id = ?""",
            (xabar, _MAX_URINISH, HOLAT_MUAMMOLI, mijoz_id),
        )
        conn.commit()
        qator = conn.execute(
            "SELECT urinishlar_soni, holati FROM navbat WHERE mijoz_id = ?", (mijoz_id,)
        ).fetchone()
    if qator is not None and qator[1] == HOLAT_MUAMMOLI:
        logger.warning(
            "Navbat yozuvi 'muammoli' deb belgilandi (mijoz_id=%s, %s marta muvaffaqiyatsiz, oxirgi xato: %s) — "
            "endi qayta urinilmaydi, admin ko'rishi kerak",
            mijoz_id,
            qator[0],
            xabar,
        )


def muammoli_soni() -> int:
    """Dead-letter qilingan (`_MAX_URINISH` marta muvaffaqiyatsiz) yozuvlar
    soni — admin uchun oddiy hisoblash (masalan `/holat` endpointida)."""
    conn = _ulanish()
    with _lock:
        return conn.execute("SELECT COUNT(*) FROM navbat WHERE holati = ?", (HOLAT_MUAMMOLI,)).fetchone()[0]


def muammolilarni_olish() -> list[dict]:
    """Dead-letter qilingan yozuvlarning to'liq ro'yxati (admin ko'rishi uchun)."""
    conn = _ulanish()
    with _lock:
        qatorlar = conn.execute(
            "SELECT mijoz_id, token, payload, urinishlar_soni, oxirgi_xato FROM navbat "
            "WHERE holati = ? ORDER BY yaratilgan_vaqt",
            (HOLAT_MUAMMOLI,),
        ).fetchall()
    return [
        {
            "mijoz_id": r[0],
            "token": r[1],
            "payload": json.loads(r[2]),
            "urinishlar_soni": r[3],
            "oxirgi_xato": r[4],
        }
        for r in qatorlar
    ]


def uzunlik() -> int:
    """Navbatdagi JAMI yozuvlar soni ('faol' + 'muammoli') — mavjud
    ma'no o'zgarmadi (chaqiruvchilar buni "jami backlog" deb ishlatadi);
    faqat 'muammoli' (dead-letter) soni uchun `muammoli_soni()`ni ishlating."""
    conn = _ulanish()
    with _lock:
        return conn.execute("SELECT COUNT(*) FROM navbat").fetchone()[0]

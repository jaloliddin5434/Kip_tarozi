import json
import sqlite3
import threading
from pathlib import Path

from app.core.config import settings

_lock = threading.Lock()
_conn: sqlite3.Connection | None = None


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
                """CREATE TABLE IF NOT EXISTS navbat (
                    mijoz_id TEXT PRIMARY KEY,
                    token TEXT NOT NULL,
                    payload TEXT NOT NULL,
                    yaratilgan_vaqt TEXT NOT NULL,
                    urinishlar_soni INTEGER NOT NULL DEFAULT 0,
                    oxirgi_xato TEXT
                )"""
            )
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
    conn = _ulanish()
    with _lock:
        qatorlar = conn.execute(
            "SELECT mijoz_id, token, payload, urinishlar_soni FROM navbat ORDER BY yaratilgan_vaqt"
        ).fetchall()
    return [{"mijoz_id": r[0], "token": r[1], "payload": json.loads(r[2]), "urinishlar_soni": r[3]} for r in qatorlar]


def ochirish(mijoz_id: str) -> None:
    conn = _ulanish()
    with _lock:
        conn.execute("DELETE FROM navbat WHERE mijoz_id = ?", (mijoz_id,))
        conn.commit()


def xato_belgila(mijoz_id: str, xabar: str) -> None:
    conn = _ulanish()
    with _lock:
        conn.execute(
            "UPDATE navbat SET urinishlar_soni = urinishlar_soni + 1, oxirgi_xato = ? WHERE mijoz_id = ?",
            (xabar, mijoz_id),
        )
        conn.commit()


def uzunlik() -> int:
    conn = _ulanish()
    with _lock:
        return conn.execute("SELECT COUNT(*) FROM navbat").fetchone()[0]

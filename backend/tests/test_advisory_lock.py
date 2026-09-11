"""Ko'p-worker himoyasi (audit topilmasi tuzatishi): `app/services/
advisory_lock.py` — PostgreSQL `pg_try_advisory_lock` orqali faqat bitta
worker/instance biror jarayonni (Telegram polling, kunlik hisobot
rejalashtiruvchisi) haqiqatan ishga tushirishini ta'minlaydi.

Bu yerda IKKI DARAJADA sinaladi:
1. `advisory_lock.olishga_urin`/`boshatish` — REAL Postgres (test bazasi)
   ustida, haqiqiy ikkita alohida DB ulanish bilan (lock semantikasining
   o'zi to'g'ri ishlashini tasdiqlash uchun).
2. `telegram_polling`/`rejalashtiruvchi` — `advisory_lock.olishga_urin`
   soxtalashtirilib (lock "band" yoki "bo'sh" simulyatsiya qilinadi),
   ishga_tushir()/toxtat() to'g'ri javob berishini (thread/scheduler
   boshlanadi yoki boshlanmaydi) tekshiradi — bu qismda haqiqiy Telegram/DB
   pollinggа umuman chiqilmaydi.
"""

from unittest.mock import MagicMock

from app.services import advisory_lock, rejalashtiruvchi, telegram_polling

LOCK_KALITI_SINOV = 9988001
LOCK_KALITI_SINOV_2 = 9988002

# `conftest.py`dagi autouse fixture'lar (`_telegram_polling_ochirilgan`,
# `_rejalashtiruvchi_ochirilgan`) HAR bir testda `ishga_tushir`/`toxtat`ni
# no-op bilan almashtiradi (real dev bazaga/Telegramga chiqib ketmasin
# uchun) — bu FAYL esa aynan shu funksiyalarning ICHKI (advisory lock)
# mantig'ini sinaydi, shuning uchun asl funksiyalarni MODUL yuklanish
# vaqtida (har qanday fixture ishga tushishidan OLDIN) saqlab qo'yamiz va
# tegishli testlarda ularni monkeypatch bilan QAYTA tiklaymiz.
_ASL_TELEGRAM_ISHGA_TUSHIR = telegram_polling.ishga_tushir
_ASL_TELEGRAM_TOXTAT = telegram_polling.toxtat
_ASL_REJALASHTIRUVCHI_ISHGA_TUSHIR = rejalashtiruvchi.ishga_tushir
_ASL_REJALASHTIRUVCHI_TOXTAT = rejalashtiruvchi.toxtat


# --- 1) advisory_lock.py — real Postgres (test bazasi) ustida ---


def test_lock_olinadi(engine):
    conn = advisory_lock.olishga_urin(LOCK_KALITI_SINOV, "sinov", db_engine=engine)
    assert conn is not None
    advisory_lock.boshatish(conn, "sinov")


def test_ikkinchi_ulanish_band_kalitni_olmaydi(engine):
    """Ikkita ALOHIDA DB ulanish — birinchisi lockni ushlab tursa,
    ikkinchisi bir xil kalit uchun None (muvaffaqiyatsiz) qaytarishi
    kerak."""
    birinchi = advisory_lock.olishga_urin(LOCK_KALITI_SINOV, "birinchi", db_engine=engine)
    assert birinchi is not None
    try:
        ikkinchi = advisory_lock.olishga_urin(LOCK_KALITI_SINOV, "ikkinchi", db_engine=engine)
        assert ikkinchi is None
    finally:
        advisory_lock.boshatish(birinchi, "birinchi")


def test_birinchi_boshatilgandan_keyin_boshqasi_ola_oladi(engine):
    birinchi = advisory_lock.olishga_urin(LOCK_KALITI_SINOV, "birinchi", db_engine=engine)
    assert birinchi is not None
    advisory_lock.boshatish(birinchi, "birinchi")

    ikkinchi = advisory_lock.olishga_urin(LOCK_KALITI_SINOV, "ikkinchi", db_engine=engine)
    assert ikkinchi is not None
    advisory_lock.boshatish(ikkinchi, "ikkinchi")


def test_ulanish_ozi_yopilsa_lock_avtomatik_boshaydi(engine):
    """`boshatish()` chaqirilmasa ham (masalan worker kutilmaganda o'lsa),
    ulanishning o'zi yopilishi (`conn.close()`) bilan Postgres lockni
    avtomatik bo'shatadi — qo'lda `pg_advisory_unlock` shart emas."""
    birinchi = advisory_lock.olishga_urin(LOCK_KALITI_SINOV, "birinchi", db_engine=engine)
    assert birinchi is not None
    birinchi.close()  # advisory_lock.boshatish() EMAS — to'g'ridan-to'g'ri yopish

    ikkinchi = advisory_lock.olishga_urin(LOCK_KALITI_SINOV, "ikkinchi", db_engine=engine)
    assert ikkinchi is not None
    advisory_lock.boshatish(ikkinchi, "ikkinchi")


def test_ikkita_boshqa_kalit_bir_biriga_taqiqlanmaydi(engine):
    """Turli kalitlar (masalan telegram_polling va rejalashtiruvchi uchun)
    bir-biriga ta'sir qilmasligi kerak — ikkalasi ham BIR VAQTDA olinadi."""
    a = advisory_lock.olishga_urin(LOCK_KALITI_SINOV, "A", db_engine=engine)
    b = advisory_lock.olishga_urin(LOCK_KALITI_SINOV_2, "B", db_engine=engine)
    try:
        assert a is not None
        assert b is not None
    finally:
        advisory_lock.boshatish(a, "A")
        advisory_lock.boshatish(b, "B")


def test_boshatish_none_bilan_xato_bermaydi():
    advisory_lock.boshatish(None, "hech narsa yo'q")


def test_telegram_polling_va_rejalashtiruvchi_turli_kalit_ishlatadi():
    """Item 4 talabi: ikkita mustaqil, aniq farqli lock kaliti."""
    assert telegram_polling.LOCK_KALITI != rejalashtiruvchi.LOCK_KALITI


# --- 2) telegram_polling / rejalashtiruvchi — ishga_tushir()/toxtat() wiring ---


def test_telegram_polling_lock_band_bolsa_thread_boshlanmaydi(monkeypatch):
    monkeypatch.setattr(telegram_polling, "ishga_tushir", _ASL_TELEGRAM_ISHGA_TUSHIR)
    monkeypatch.setattr(telegram_polling, "_thread", None)
    monkeypatch.setattr(telegram_polling, "_lock_ulanishi", None)
    monkeypatch.setattr(telegram_polling.advisory_lock, "olishga_urin", lambda *a, **kw: None)

    telegram_polling.ishga_tushir()

    assert telegram_polling._thread is None
    assert telegram_polling._lock_ulanishi is None


def test_telegram_polling_lock_erkin_bolsa_thread_boshlanadi(monkeypatch):
    soxta_ulanish = MagicMock()
    monkeypatch.setattr(telegram_polling, "ishga_tushir", _ASL_TELEGRAM_ISHGA_TUSHIR)
    monkeypatch.setattr(telegram_polling, "toxtat", _ASL_TELEGRAM_TOXTAT)
    monkeypatch.setattr(telegram_polling, "_thread", None)
    monkeypatch.setattr(telegram_polling, "_lock_ulanishi", None)
    monkeypatch.setattr(telegram_polling.advisory_lock, "olishga_urin", lambda *a, **kw: soxta_ulanish)
    # Real Telegramga chiqmasin — _tsikl() token yo'qligi sababli darhol
    # `_toxtatish_signali.wait(2)`ga tushadi, lekin ehtiyot uchun bitta_tsikl'ni
    # ham soxtalashtiramiz.
    monkeypatch.setattr(telegram_polling, "bitta_tsikl", lambda db: [])

    try:
        telegram_polling.ishga_tushir()
        assert telegram_polling._thread is not None
        assert telegram_polling._thread.is_alive()
        assert telegram_polling._lock_ulanishi is soxta_ulanish
    finally:
        telegram_polling.toxtat()

    soxta_ulanish.close.assert_called_once()
    assert telegram_polling._lock_ulanishi is None


def test_rejalashtiruvchi_lock_band_bolsa_scheduler_ishga_tushmaydi(monkeypatch):
    # DIQQAT: `_scheduler` modul darajasidagi YAGONA (butun test sessiyasi
    # bilan bo'lishiladigan) singleton — uni haqiqatan start/shutdown qilish
    # APScheduler'ni qayta ishga tushirib bo'lmaydigan holatga olib kelishi
    # mumkin. Shu sabab bu yerda soxta (mock) scheduler bilan almashtiramiz.
    soxta_scheduler = MagicMock()
    soxta_scheduler.running = False
    monkeypatch.setattr(rejalashtiruvchi, "ishga_tushir", _ASL_REJALASHTIRUVCHI_ISHGA_TUSHIR)
    monkeypatch.setattr(rejalashtiruvchi, "_scheduler", soxta_scheduler)
    monkeypatch.setattr(rejalashtiruvchi, "_lock_ulanishi", None)
    monkeypatch.setattr(rejalashtiruvchi.advisory_lock, "olishga_urin", lambda *a, **kw: None)

    rejalashtiruvchi.ishga_tushir()

    assert rejalashtiruvchi._lock_ulanishi is None
    soxta_scheduler.add_job.assert_not_called()
    soxta_scheduler.start.assert_not_called()


def test_rejalashtiruvchi_lock_erkin_bolsa_ishga_tushadi(monkeypatch):
    soxta_ulanish = MagicMock()
    soxta_scheduler = MagicMock()
    soxta_scheduler.running = False
    monkeypatch.setattr(rejalashtiruvchi, "ishga_tushir", _ASL_REJALASHTIRUVCHI_ISHGA_TUSHIR)
    monkeypatch.setattr(rejalashtiruvchi, "toxtat", _ASL_REJALASHTIRUVCHI_TOXTAT)
    monkeypatch.setattr(rejalashtiruvchi, "_scheduler", soxta_scheduler)
    monkeypatch.setattr(rejalashtiruvchi, "_lock_ulanishi", None)
    monkeypatch.setattr(rejalashtiruvchi.advisory_lock, "olishga_urin", lambda *a, **kw: soxta_ulanish)

    rejalashtiruvchi.ishga_tushir()
    assert rejalashtiruvchi._lock_ulanishi is soxta_ulanish
    soxta_scheduler.add_job.assert_called_once()
    soxta_scheduler.start.assert_called_once()

    rejalashtiruvchi.toxtat()
    soxta_ulanish.close.assert_called_once()
    assert rejalashtiruvchi._lock_ulanishi is None

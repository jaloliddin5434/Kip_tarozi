"""Stansiya Agentining offline SQLite navbati — DB (Postgres) shart emas."""

import sqlite3
import threading
import time

from app.services.rs232 import navbat


def test_birinchi_ulanish_bir_nechta_thread_bilan_race_bermaydi(tmp_path, monkeypatch):
    """Task H tekshiruvida topilgan flaky xato: `_ulanish()`dagi qulfsiz
    "if _conn is None" tekshiruvi tufayli, BIRINCHI ulanishga bir nechta
    thread bir vaqtda urinsa (masalan fon SinxronIshchisi va asosiy so'rov),
    ba'zilari jadval hali yaratilmagan ulanishni ko'rib "no such table: navbat"
    xatosiga uchrashi mumkin edi.

    Haqiqiy SQLite ulanish+jadval yaratish shu qadar tez bajariladiki (GIL
    bilan birga), oddiy ko'p-thread testi tasodifiy o'tib ketishi mumkin —
    shuning uchun `sqlite3.connect` ni atayin bir oz SEKINLASHTIRAMIZ (10ms),
    "ulanish boshlandi-yu hali tugamagan" oynasini KAFOLATLANGAN tarzda
    kengaytirib, qulf yo'qligida albatta bitta thread jadval hali yo'q
    ulanishni ko'rib qolishini ta'minlaymiz. Qulf to'g'ri ishlasa — barcha
    30 ta thread xatosiz, bir xil natija (0) bilan tugashi kerak."""
    from app.core.config import settings

    monkeypatch.setattr(settings, "AGENT_QUEUE_DB_PATH", str(tmp_path / "navbat.db"))
    monkeypatch.setattr(navbat, "_conn", None)

    # Xavfli oyna aslida "ulanish tayinlangach, lekin CREATE TABLE hali
    # bajarilmagan" oralig'ida — shuning uchun sekinlashtirishni AYNAN
    # birinchi `execute()` (CREATE TABLE) chaqiruviga joylashtiramiz, connect()
    # o'ziga emas (aks holda faqat "_conn hali None" deb hisoblash payti
    # kechikadi, real xavfli oyna kengaymaydi). `sqlite3.Connection`
    # instansiyasiga to'g'ridan-to'g'ri atribut yozib bo'lmaydi (C kengaytma
    # turi) — shuning uchun `factory=` orqali kichik subklass ishlatamiz.
    class SekinConnection(sqlite3.Connection):
        _birinchi = True

        def execute(self, *a, **kw):
            if SekinConnection._birinchi:
                SekinConnection._birinchi = False
                time.sleep(0.01)
            return super().execute(*a, **kw)

    haqiqiy_connect = sqlite3.connect

    def sekin_connect(*args, **kwargs):
        kwargs["factory"] = SekinConnection
        return haqiqiy_connect(*args, **kwargs)

    monkeypatch.setattr(navbat.sqlite3, "connect", sekin_connect)

    natijalar: list[int] = []
    xatolar: list[BaseException] = []
    tayyor = threading.Barrier(30)

    def ish():
        tayyor.wait()  # barcha thread AYNAN shu nuqtada birga boshlashi uchun
        try:
            natijalar.append(navbat.uzunlik())
        except BaseException as exc:  # noqa: BLE001 — testda har qanday xatoni ushlaymiz
            xatolar.append(exc)

    threadlar = [threading.Thread(target=ish) for _ in range(30)]
    for t in threadlar:
        t.start()
    for t in threadlar:
        t.join(timeout=10)

    assert xatolar == [], f"race condition qaytadi: {xatolar}"
    assert natijalar == [0] * 30


def test_navbat_dedup_va_amallar(tmp_path, monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "AGENT_QUEUE_DB_PATH", str(tmp_path / "navbat.db"))
    monkeypatch.setattr(navbat, "_conn", None)  # yangi faylga qayta ulanish uchun

    assert navbat.uzunlik() == 0

    navbat.qoshish("uuid-1", "token-abc", {"partiya_id": 1, "ogirlik": 135.5})
    navbat.qoshish("uuid-2", "token-abc", {"partiya_id": 1, "ogirlik": 136.0})
    navbat.qoshish("uuid-1", "token-abc", {"partiya_id": 1, "ogirlik": 135.5})  # dublikat
    assert navbat.uzunlik() == 2

    elementlar = navbat.hammasini_olish()
    assert len(elementlar) == 2
    assert elementlar[0]["mijoz_id"] == "uuid-1"

    navbat.xato_belgila("uuid-1", "aloqa xatosi")
    assert navbat.hammasini_olish()[0]["urinishlar_soni"] == 1

    navbat.ochirish("uuid-1")
    assert navbat.uzunlik() == 1

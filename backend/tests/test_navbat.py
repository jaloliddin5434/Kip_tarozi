"""Stansiya Agentining offline SQLite navbati — DB (Postgres) shart emas."""

from app.services.rs232 import navbat


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

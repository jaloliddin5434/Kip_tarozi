"""Stansiya Agenti RS232 (tarozi) ulanmagan bo'lsa ham ishga tushishi kerak —
DB (Postgres) shart emas, real seriya port ham shart emas.
"""

import time

import pytest
from fastapi.testclient import TestClient

from app.core.config import settings
from app.services.rs232 import navbat, station_agent
from app.services.rs232.bus import OgirlikKanali
from app.services.rs232.reader import OgirlikOquvchi, RS232OqishXatosi
from app.services.rs232.watchdog import RS232Watchdog

MAVJUD_BOLMAGAN_PORT = "COM_YOQ_9999"
JPEG = b"\xff\xd8\xff\xe0agent\xff\xd9"


def test_ulan_notogri_port_rs232xatosi_qaytaradi(monkeypatch):
    monkeypatch.setattr(settings, "RS232_PORT", MAVJUD_BOLMAGAN_PORT)
    oquvchi = OgirlikOquvchi(OgirlikKanali())

    # Raw serial.SerialException EMAS — domen xatosi (RS232OqishXatosi)
    with pytest.raises(RS232OqishXatosi):
        oquvchi.ulan()


def test_watchdog_ulanmasa_ham_yiqilmaydi(monkeypatch):
    monkeypatch.setattr(settings, "RS232_PORT", MAVJUD_BOLMAGAN_PORT)
    monkeypatch.setattr(settings, "RS232_RECONNECT_SECONDS", 0.2)
    wd = RS232Watchdog(OgirlikOquvchi(OgirlikKanali()))
    try:
        wd.ishga_tushir()
        # Bir necha urinishga vaqt beramiz
        for _ in range(30):
            if wd.holat.qayta_urinishlar >= 2:
                break
            time.sleep(0.1)
        assert wd.holat.ulangan is False
        assert wd.holat.oxirgi_xato is not None
        assert wd.holat.qayta_urinishlar >= 1
        assert wd._thread is not None and wd._thread.is_alive()  # thread yiqilmagan
    finally:
        wd.toxtat()


def test_agent_rs232siz_ishga_tushadi_kamera_ishlaydi(tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "RS232_PORT", MAVJUD_BOLMAGAN_PORT)
    monkeypatch.setattr(settings, "RS232_RECONNECT_SECONDS", 0.2)
    monkeypatch.setattr(settings, "AGENT_QUEUE_DB_PATH", str(tmp_path / "navbat.db"))
    monkeypatch.setattr(navbat, "_conn", None)
    monkeypatch.setattr(station_agent, "kamera_snapshot_ol", lambda: JPEG)

    # lifespan (watchdog + fon thread'lar) ishga tushadi — SerialException
    # butun Agentni yiqitmasligi kerak.
    with TestClient(station_agent.app) as client:
        # Tarozi-ga bog'liq bo'lmagan endpoint normal ishlaydi
        surat = client.get("/kamera/surat")
        assert surat.status_code == 200
        assert surat.content == JPEG

        # RS232 holati "ulanmagan" deb aniq qaytariladi (crash emas)
        holat = client.get("/holat")
        assert holat.status_code == 200
        data = holat.json()
        assert data["ulangan"] is False
        assert data["joriy_ogirlik"] == 0.0
        assert data["barqarormi"] is False

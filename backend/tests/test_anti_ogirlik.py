"""Anti-o'g'irlik state machine — sof mantiq, DB/RS232 shart emas."""

import time
from datetime import datetime, timedelta, timezone

import pytest

from app.services.rs232.anti_ogirlik import AntiOgirlikHolati, AntiOgirlikNazorati
from app.services.rs232.bus import OgirlikKanali


@pytest.fixture(autouse=True)
def _sozlamalar(monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "ANTI_OGIRLIK_THRESHOLD_KG", 130.0)
    monkeypatch.setattr(settings, "ANTI_OGIRLIK_PASTGA_TUSHISH_KG", 10.0)
    monkeypatch.setattr(settings, "STABILITY_SECONDS", 3.0)


def test_normal_yol_saqlandi():
    kanal = OgirlikKanali()
    hodisalar = []
    nazorat = AntiOgirlikNazorati(kanal, lambda *a: hodisalar.append(a) or 1)

    b = datetime.now(timezone.utc)
    kanal.eshittir(0, b)
    assert nazorat.holat == AntiOgirlikHolati.bosh

    kanal.eshittir(135, b)
    kanal.eshittir(135, b + timedelta(seconds=3.1))
    assert nazorat.holat == AntiOgirlikHolati.yuk_qoyildi

    nazorat.saqlandi_deb_belgila()
    assert nazorat.holat == AntiOgirlikHolati.bosh
    assert hodisalar == []


def test_qisqa_barqarorlik_yetarli_emas():
    kanal = OgirlikKanali()
    nazorat = AntiOgirlikNazorati(kanal, lambda *a: 1)

    b = datetime.now(timezone.utc)
    kanal.eshittir(135, b)
    kanal.eshittir(135, b + timedelta(seconds=1))
    assert nazorat.holat == AntiOgirlikHolati.bosh


def test_yuk_saqlanmadi_hodisasi():
    kanal = OgirlikKanali()
    hodisalar = []
    nazorat = AntiOgirlikNazorati(kanal, lambda ogirlik, vaqt, smena, mahsulot: hodisalar.append((ogirlik, smena, mahsulot)) or 42)
    nazorat.kontekst_ornat("tola", "A")

    b = datetime.now(timezone.utc)
    kanal.eshittir(140, b)
    kanal.eshittir(140, b + timedelta(seconds=3.1))
    assert nazorat.holat == AntiOgirlikHolati.yuk_qoyildi

    kanal.eshittir(5, b + timedelta(seconds=4))
    assert nazorat.holat == AntiOgirlikHolati.bloklangan

    time.sleep(0.3)  # hodisa alohida thread'da yuboriladi
    assert hodisalar == [(5, "A", "tola")]
    assert nazorat.joriy_hodisa_id == 42

    # bloklangan holatda yangi og'irlik holatni o'zgartirmaydi
    kanal.eshittir(140, b + timedelta(seconds=10))
    assert nazorat.holat == AntiOgirlikHolati.bloklangan

    nazorat.tasdiqlandi()
    assert nazorat.holat == AntiOgirlikHolati.bosh
    assert nazorat.joriy_hodisa_id is None

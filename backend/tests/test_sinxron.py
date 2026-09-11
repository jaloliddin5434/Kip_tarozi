"""Stansiya Agentining offline navbatini backendga yuborish (`SinxronIshchisi`).

AUDIT TOPILMASI TUZATISHI: navbat endi BO'LAKLARGA (`sinxron._BOLAK_HAJMI`)
bo'lib yuboriladi, har bo'lak muvaffaqiyatli bo'lgach DARHOL navbatdan
o'chiriladi — shuning uchun keyingi bo'lak/tsikl muvaffaqiyatsiz bo'lsa ham
oldingi bo'laklar yo'qolmaydi (eski xatti-harakat: butun navbat BITTA
so'rovda, katta navbatda HECH QACHON muvaffaqiyatli tugamas edi).

Real Postgres/HTTP kerak emas — `httpx.post` mocklanadi (loyihadagi yagona
mocking uslubi), SQLite navbat `tmp_path`da.
"""

import httpx
import pytest

from app.core.config import settings
from app.services.rs232 import navbat, sinxron


@pytest.fixture(autouse=True)
def _sinov_navbati(tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "AGENT_QUEUE_DB_PATH", str(tmp_path / "navbat.db"))
    monkeypatch.setattr(navbat, "_conn", None)


def _javob_yasa(mijoz_idlar: list[str], holat: str = "saqlandi") -> httpx.Response:
    natijalar = [{"mijoz_id": mid, "holat": holat, "kip_id": i + 1} for i, mid in enumerate(mijoz_idlar)]
    return httpx.Response(200, json=natijalar, request=httpx.Request("POST", "https://example.test/sinxron"))


def _sorovdagi_mijoz_idlar(kwargs: dict) -> list[str]:
    # sinxron.py `json=[g["payload"] for g in bolak]` yuboradi — payload'da
    # mijoz_id yo'q, shuning uchun testda navbatni `mijoz_id`ni payload
    # ichiga ham yozib to'ldiramiz (pastga qarang, _navbatni_toldir_payloadda_id_bilan).
    return [q["mijoz_id"] for q in kwargs["json"]]


def _navbatni_toldir_payloadda_id_bilan(soni: int, token: str = "token-abc") -> list[str]:
    idlar = []
    for i in range(soni):
        mid = f"mijoz-{token}-{i}"
        navbat.qoshish(mid, token, {"mijoz_id": mid, "partiya_id": 1, "ogirlik": 100.0 + i})
        idlar.append(mid)
    return idlar


# --- Asosiy: katta navbat bo'laklarga bo'linadi ---


def test_katta_navbat_bolaklarga_bolinib_yuboriladi(monkeypatch):
    idlar = _navbatni_toldir_payloadda_id_bilan(220)
    assert navbat.uzunlik() == 220

    sorovlar: list[dict] = []

    def soxta_post(url, **kwargs):
        yuborilgan_idlar = _sorovdagi_mijoz_idlar(kwargs)
        sorovlar.append({"url": url, "idlar": yuborilgan_idlar, "headers": kwargs.get("headers")})
        return _javob_yasa(yuborilgan_idlar)

    monkeypatch.setattr(sinxron.httpx, "post", soxta_post)
    sinxron.SinxronIshchisi()._urinish()

    # 220 ta yozuv, 50 tadan bo'lak -> 5 ta so'rov (4x50 + 1x20)
    assert len(sorovlar) == 5
    for s in sorovlar[:4]:
        assert len(s["idlar"]) == 50
    assert len(sorovlar[-1]["idlar"]) == 20

    # Barcha bo'laklar birma-bir navbatdan o'chirilgan bo'lishi kerak
    assert navbat.uzunlik() == 0
    # Hech bir mijoz_id ikki marta yuborilmagan (bo'laklar bir-birini qoplamaydi)
    barcha_yuborilgan = [mid for s in sorovlar for mid in s["idlar"]]
    assert sorted(barcha_yuborilgan) == sorted(idlar)


def test_bolak_hajmi_va_timeout_muvozanati():
    """Item 3 — bo'lak hajmi va timeout birgalikda "hech qachon vaqt
    tugamaydigan" muvozanatga kelishi kerak: eski 15s/cheksiz-hajm
    o'rniga endi cheklangan hajm + kengaytirilgan timeout."""
    assert sinxron._BOLAK_HAJMI <= 100
    assert sinxron._SOROV_TIMEOUT_SONIYA >= 30
    # Har yozuvga "byudjet" (masalan sekin Telegram so'rovlarini ham
    # qamrab olish uchun) kamida 1 soniya bo'lishi kerak.
    assert sinxron._SOROV_TIMEOUT_SONIYA / sinxron._BOLAK_HAJMI >= 1.0


# --- Bitta bo'lak muvaffaqiyatsiz bo'lsa — oldingi bo'laklar saqlanadi ---


def test_bolak_muvaffaqiyatsiz_bolsa_oldingi_bolaklar_saqlanadi(monkeypatch):
    """120 ta yozuv (3 ta bo'lak: 50+50+20). 1-bo'lak muvaffaqiyatli,
    2-bo'lakda tarmoq xatosi (masalan internet uzilishi simulyatsiyasi) —
    1-bo'lak baribir navbatdan o'chirilgan bo'lishi, 2- va 3-bo'lak esa
    TEGILMAGAN holda navbatda qolishi kerak."""
    idlar = _navbatni_toldir_payloadda_id_bilan(120)
    chaqiruvlar_soni = 0

    def soxta_post(url, **kwargs):
        nonlocal chaqiruvlar_soni
        chaqiruvlar_soni += 1
        yuborilgan_idlar = _sorovdagi_mijoz_idlar(kwargs)
        if chaqiruvlar_soni == 2:
            raise httpx.ConnectError("internet uzildi (simulyatsiya)")
        return _javob_yasa(yuborilgan_idlar)

    monkeypatch.setattr(sinxron.httpx, "post", soxta_post)

    ishchi = sinxron.SinxronIshchisi()
    ishchi._urinish()  # istisno tashlamasligi kerak (ichkarida ushlanadi)

    assert chaqiruvlar_soni == 2  # 3-bo'lakka umuman yetib bormagan
    qolganlar = {q["mijoz_id"] for q in navbat.hammasini_olish()}
    # Birinchi 50 ta (1-bo'lak) o'chirilgan, qolgan 70 ta (2- va 3-bo'lak) navbatda qoladi
    assert navbat.uzunlik() == 70
    assert qolganlar == set(idlar[50:])
    assert set(idlar[:50]).isdisjoint(qolganlar)


def test_keyingi_tsiklda_qolgan_bolaklar_davom_etadi(monkeypatch):
    """Yuqoridagi stsenariyning davomi: birinchi `_urinish()` yarim yo'lda
    to'xtagach, IKKINCHI chaqiruv (keyingi tsikl simulyatsiyasi) qolgan
    yozuvlarni muvaffaqiyatli tugatishi kerak — navbat oxir-oqibat butunlay
    bo'shaydi."""
    _navbatni_toldir_payloadda_id_bilan(120)

    chaqiruvlar_soni = 0

    def soxta_post_birinchi_marta_uzilgan(url, **kwargs):
        nonlocal chaqiruvlar_soni
        chaqiruvlar_soni += 1
        if chaqiruvlar_soni == 2:
            raise httpx.ConnectError("internet uzildi (simulyatsiya)")
        return _javob_yasa(_sorovdagi_mijoz_idlar(kwargs))

    monkeypatch.setattr(sinxron.httpx, "post", soxta_post_birinchi_marta_uzilgan)
    ishchi = sinxron.SinxronIshchisi()
    ishchi._urinish()
    assert navbat.uzunlik() == 70  # 1-bo'lak ketdi, qolgani turibdi

    # "Internet tiklandi" — endi hamma so'rov muvaffaqiyatli
    monkeypatch.setattr(sinxron.httpx, "post", lambda url, **kwargs: _javob_yasa(_sorovdagi_mijoz_idlar(kwargs)))
    ishchi._urinish()
    assert navbat.uzunlik() == 0


# --- Turli operator tokenlari mustaqil guruhlanadi ---


def test_ikki_token_alohida_guruhlanadi(monkeypatch):
    idlar_a = _navbatni_toldir_payloadda_id_bilan(60, token="token-A")
    idlar_b = _navbatni_toldir_payloadda_id_bilan(30, token="token-B")

    sorovlar: list[dict] = []

    def soxta_post(url, **kwargs):
        sorovlar.append({"headers": kwargs["headers"], "idlar": _sorovdagi_mijoz_idlar(kwargs)})
        return _javob_yasa(_sorovdagi_mijoz_idlar(kwargs))

    monkeypatch.setattr(sinxron.httpx, "post", soxta_post)
    sinxron.SinxronIshchisi()._urinish()

    # token-A: 60 ta -> 2 bo'lak (50+10); token-B: 30 ta -> 1 bo'lak
    assert len(sorovlar) == 3
    a_sorovlari = [s for s in sorovlar if s["headers"]["Authorization"] == "Bearer token-A"]
    b_sorovlari = [s for s in sorovlar if s["headers"]["Authorization"] == "Bearer token-B"]
    assert len(a_sorovlari) == 2
    assert sorted(mid for s in a_sorovlari for mid in s["idlar"]) == sorted(idlar_a)
    assert len(b_sorovlari) == 1
    assert sorted(b_sorovlari[0]["idlar"]) == sorted(idlar_b)
    assert navbat.uzunlik() == 0


# --- Xato holat navbatda qoladi (o'chirilmaydi) ---


def test_xato_natija_navbatdan_ochirilmaydi_urinish_belgilanadi(monkeypatch):
    idlar = _navbatni_toldir_payloadda_id_bilan(3)

    def soxta_post(url, **kwargs):
        yuborilgan = _sorovdagi_mijoz_idlar(kwargs)
        natijalar = [
            {"mijoz_id": mid, "holat": "xato", "xabar": "Partiya topilmadi"}
            if mid == yuborilgan[0]
            else {"mijoz_id": mid, "holat": "saqlandi", "kip_id": 1}
            for mid in yuborilgan
        ]
        return httpx.Response(200, json=natijalar, request=httpx.Request("POST", url))

    monkeypatch.setattr(sinxron.httpx, "post", soxta_post)
    sinxron.SinxronIshchisi()._urinish()

    qolganlar = navbat.hammasini_olish()
    assert len(qolganlar) == 1
    assert qolganlar[0]["mijoz_id"] == idlar[0]
    assert qolganlar[0]["urinishlar_soni"] == 1


def test_bosh_navbat_sorov_yubormaydi(monkeypatch):
    chaqirildimi = False

    def soxta_post(url, **kwargs):
        nonlocal chaqirildimi
        chaqirildimi = True
        return _javob_yasa([])

    monkeypatch.setattr(sinxron.httpx, "post", soxta_post)
    sinxron.SinxronIshchisi()._urinish()
    assert chaqirildimi is False

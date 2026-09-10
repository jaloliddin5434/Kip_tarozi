"""Kip surati "surat boti"ga yuboriladi (telegram.surat_yubor).

Hech bir test real Telegram'ga chiqmaydi — httpx.post har doim mocklanadi.
"""

import uuid
from datetime import datetime, timezone

import httpx
import pytest

from app.core.config import settings
from app.models.sozlama import Sozlama
from app.services import telegram

SOXTA_JPEG = b"\xff\xd8\xff\xe0\x00\x10JFIF" + b"\x00" * 20 + b"\xff\xd9"


@pytest.fixture()
def surat_boti_sozlangan(db):
    db.add(Sozlama(kalit=telegram.SURAT_TOKEN_KALITI, qiymat="123:ABC"))
    db.add(Sozlama(kalit=telegram.SURAT_CHAT_KALITI, qiymat="7250979081"))
    db.commit()


@pytest.fixture()
def surat_fayli(monkeypatch, tmp_path):
    monkeypatch.setattr(settings, "STORAGE_PATH", str(tmp_path))
    nisbiy = "2026-09/2026-09-08/Smena_A/Tola/foto.jpg"
    fayl = tmp_path / nisbiy
    fayl.parent.mkdir(parents=True, exist_ok=True)
    fayl.write_bytes(SOXTA_JPEG)
    return nisbiy


def test_surat_yubor_sendphoto_chaqiradi(db, monkeypatch, surat_boti_sozlangan, surat_fayli):
    chaqiruvlar = {}

    def soxta_post(url, **kw):
        chaqiruvlar["url"] = url
        chaqiruvlar["data"] = kw.get("data")
        chaqiruvlar["files"] = kw.get("files")
        return httpx.Response(200, json={"ok": True}, request=httpx.Request("POST", url))

    monkeypatch.setattr(telegram.httpx, "post", soxta_post)

    telegram.surat_yubor(db, surat_fayli, "Tola", 7, 42, 204.7)

    assert chaqiruvlar["url"].endswith("/bot123:ABC/sendPhoto")
    assert chaqiruvlar["data"] == {
        "chat_id": "7250979081",
        "caption": "Mahsulot: Tola\nPartiya: #7\nKip №42\nOg'irlik: 204.7 kg",
    }
    assert "photo" in chaqiruvlar["files"]


def test_ogirlik_bir_xona_kasr_bilan(db, monkeypatch, surat_boti_sozlangan, surat_fayli):
    captured = {}
    monkeypatch.setattr(
        telegram.httpx,
        "post",
        lambda url, **kw: captured.update(kw.get("data") or {})
        or httpx.Response(200, json={"ok": True}, request=httpx.Request("POST", url)),
    )
    telegram.surat_yubor(db, surat_fayli, "Lint", 55, 3, 130)  # butun son ham
    assert "Og'irlik: 130.0 kg" in captured["caption"]


def test_surat_yoq_bolsa_hech_narsa_yubormaydi(db, monkeypatch, surat_boti_sozlangan):
    monkeypatch.setattr(
        telegram.httpx, "post", lambda *a, **k: (_ for _ in ()).throw(AssertionError("chaqirilmasligi kerak"))
    )
    telegram.surat_yubor(db, None, "Tola", 1, 1, 100.0)  # surat_yoli yo'q


def test_sozlanmagan_bot_jimgina_otkazadi(db, monkeypatch, surat_fayli):
    # Sozlama yo'q — httpx umuman chaqirilmasligi kerak
    monkeypatch.setattr(
        telegram.httpx, "post", lambda *a, **k: (_ for _ in ()).throw(AssertionError("chaqirilmasligi kerak"))
    )
    telegram.surat_yubor(db, surat_fayli, "Tola", 1, 1, 100.0)


def test_fayl_topilmasa_jimgina_otkazadi(db, monkeypatch, surat_boti_sozlangan, tmp_path):
    monkeypatch.setattr(settings, "STORAGE_PATH", str(tmp_path))
    monkeypatch.setattr(
        telegram.httpx, "post", lambda *a, **k: (_ for _ in ()).throw(AssertionError("chaqirilmasligi kerak"))
    )
    telegram.surat_yubor(db, "yoq/fayl.jpg", "Tola", 1, 1, 100.0)


def test_telegram_xatosi_yutiladi(db, monkeypatch, surat_boti_sozlangan, surat_fayli):
    def portlaydi(*a, **k):
        raise httpx.ConnectError("tarmoq yo'q")

    monkeypatch.setattr(telegram.httpx, "post", portlaydi)
    telegram.surat_yubor(db, surat_fayli, "Tola", 1, 7, 55.5)  # istisno tashqariga chiqmasligi kerak


# --- 0-QISM audit: message_id qaytarilishi/saqlanishi ---


def test_surat_yubor_message_id_qaytaradi(db, monkeypatch, surat_boti_sozlangan, surat_fayli):
    """Audit natijasi: avval surat_yubor() Telegram javobidagi message_id'ni
    umuman o'qimas/qaytarmas edi. Endi qaytarishi kerak."""
    monkeypatch.setattr(
        telegram.httpx,
        "post",
        lambda url, **kw: httpx.Response(200, json={"ok": True, "result": {"message_id": 4242}}, request=httpx.Request("POST", url)),
    )
    xabar_id = telegram.surat_yubor(db, surat_fayli, "Tola", 7, 42, 204.7)
    assert xabar_id == 4242


def test_surat_yubor_javobda_result_yoq_bolsa_none(db, monkeypatch, surat_boti_sozlangan, surat_fayli):
    monkeypatch.setattr(
        telegram.httpx,
        "post",
        lambda url, **kw: httpx.Response(200, json={"ok": True}, request=httpx.Request("POST", url)),
    )
    assert telegram.surat_yubor(db, surat_fayli, "Tola", 7, 42, 204.7) is None


def test_surat_yubor_xato_bolsa_none_qaytaradi(db, monkeypatch, surat_boti_sozlangan, surat_fayli):
    monkeypatch.setattr(telegram.httpx, "post", lambda *a, **k: (_ for _ in ()).throw(httpx.ConnectError("x")))
    assert telegram.surat_yubor(db, surat_fayli, "Tola", 1, 7, 55.5) is None


def test_surat_yoq_bolsa_none_qaytaradi(db, monkeypatch, surat_boti_sozlangan):
    monkeypatch.setattr(
        telegram.httpx, "post", lambda *a, **k: (_ for _ in ()).throw(AssertionError("chaqirilmasligi kerak"))
    )
    assert telegram.surat_yubor(db, None, "Tola", 1, 1, 100.0) is None


def test_kip_saqlanganda_telegram_surat_xabar_id_bazaga_saqlanadi(
    client, db, operator_headers, mahsulot_tola, monkeypatch, tmp_path
):
    """0-QISM audit natijasiga tuzatish: message_id endi kipga saqlanadi."""
    from app.models.kip import Kip

    monkeypatch.setattr(settings, "STORAGE_PATH", str(tmp_path))
    monkeypatch.setattr(settings, "KAMERA_IP", "10.0.0.9")
    monkeypatch.setattr(settings, "KAMERA_LOGIN", "a")
    monkeypatch.setattr(settings, "KAMERA_PAROL", "b")
    monkeypatch.setattr("app.services.kamera.snapshot_ol", lambda: SOXTA_JPEG)
    db.add(Sozlama(kalit=telegram.SURAT_TOKEN_KALITI, qiymat="tok"))
    db.add(Sozlama(kalit=telegram.SURAT_CHAT_KALITI, qiymat="chat"))
    db.commit()
    monkeypatch.setattr(
        telegram.httpx,
        "post",
        lambda url, **kw: httpx.Response(200, json={"ok": True, "result": {"message_id": 555}}, request=httpx.Request("POST", url)),
    )

    partiya = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": 350}, headers=operator_headers
    ).json()
    javob = client.post("/api/v1/kiplar", json=_payload(partiya["id"]), headers=operator_headers)
    assert javob.status_code == 201

    kip = db.get(Kip, javob.json()["id"])
    assert kip.telegram_surat_xabar_id == 555


def test_kip_saqlanganda_message_id_bolmasa_maydon_null_qoladi(
    client, db, operator_headers, mahsulot_tola, monkeypatch, tmp_path
):
    from app.models.kip import Kip

    monkeypatch.setattr(settings, "STORAGE_PATH", str(tmp_path))
    monkeypatch.setattr(settings, "KAMERA_IP", "10.0.0.9")
    monkeypatch.setattr(settings, "KAMERA_LOGIN", "a")
    monkeypatch.setattr(settings, "KAMERA_PAROL", "b")
    monkeypatch.setattr("app.services.kamera.snapshot_ol", lambda: SOXTA_JPEG)
    db.add(Sozlama(kalit=telegram.SURAT_TOKEN_KALITI, qiymat="tok"))
    db.add(Sozlama(kalit=telegram.SURAT_CHAT_KALITI, qiymat="chat"))
    db.commit()
    monkeypatch.setattr(telegram.httpx, "post", lambda *a, **k: (_ for _ in ()).throw(httpx.ConnectError("x")))

    partiya = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": 351}, headers=operator_headers
    ).json()
    javob = client.post("/api/v1/kiplar", json=_payload(partiya["id"]), headers=operator_headers)
    assert javob.status_code == 201

    kip = db.get(Kip, javob.json()["id"])
    assert kip.telegram_surat_xabar_id is None


# --- surat_xabarini_yangila (editMessageCaption) ---


def test_surat_xabarini_yangila_editmessagecaption_chaqiradi(db, monkeypatch, surat_boti_sozlangan):
    chaqiruvlar = {}

    def soxta_post(url, **kw):
        chaqiruvlar["url"] = url
        chaqiruvlar["json"] = kw.get("json")
        return httpx.Response(200, json={"ok": True}, request=httpx.Request("POST", url))

    monkeypatch.setattr(telegram.httpx, "post", soxta_post)

    telegram.surat_xabarini_yangila(db, 555, "Lint", 9, 3, 88.8)

    assert chaqiruvlar["url"].endswith("/bot123:ABC/editMessageCaption")
    assert chaqiruvlar["json"]["chat_id"] == "7250979081"
    assert chaqiruvlar["json"]["message_id"] == 555
    assert chaqiruvlar["json"]["caption"] == (
        "🔄 Tuzatildi:\nMahsulot: Lint\nPartiya: #9\nKip №3\nOg'irlik: 88.8 kg"
    )


def test_surat_xabarini_yangila_xato_bolsa_yutiladi(db, monkeypatch, surat_boti_sozlangan):
    monkeypatch.setattr(telegram.httpx, "post", lambda *a, **k: (_ for _ in ()).throw(httpx.ConnectError("x")))
    telegram.surat_xabarini_yangila(db, 555, "Lint", 9, 3, 88.8)  # istisno chiqmasligi kerak


def test_surat_xabarini_yangila_sozlanmagan_bot_jimgina_otkazadi(db, monkeypatch):
    monkeypatch.setattr(
        telegram.httpx, "post", lambda *a, **k: (_ for _ in ()).throw(AssertionError("chaqirilmasligi kerak"))
    )
    telegram.surat_xabarini_yangila(db, 555, "Lint", 9, 3, 88.8)


# --- Integratsiya: kip saqlash oqimi ---


def _payload(partiya_id: int) -> dict:
    return {
        "mijoz_id": str(uuid.uuid4()),
        "partiya_id": partiya_id,
        "ogirlik": 133.0,
        "mahalliy_vaqt": datetime.now(timezone.utc).isoformat(),
    }


def test_kip_saqlanganda_surat_botiga_yuboriladi(
    client, db, operator_headers, mahsulot_tola, monkeypatch, tmp_path
):
    monkeypatch.setattr(settings, "STORAGE_PATH", str(tmp_path))
    monkeypatch.setattr(settings, "KAMERA_IP", "10.0.0.9")
    monkeypatch.setattr(settings, "KAMERA_LOGIN", "a")
    monkeypatch.setattr(settings, "KAMERA_PAROL", "b")
    monkeypatch.setattr("app.services.kamera.snapshot_ol", lambda: SOXTA_JPEG)
    db.add(Sozlama(kalit=telegram.SURAT_TOKEN_KALITI, qiymat="tok"))
    db.add(Sozlama(kalit=telegram.SURAT_CHAT_KALITI, qiymat="chat"))
    db.commit()

    yuborilgan = []

    def soxta_post(url, **kw):
        yuborilgan.append((url, kw.get("data")))
        return httpx.Response(200, json={"ok": True}, request=httpx.Request("POST", url))

    monkeypatch.setattr(telegram.httpx, "post", soxta_post)

    partiya = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": 301}, headers=operator_headers
    ).json()
    javob = client.post("/api/v1/kiplar", json=_payload(partiya["id"]), headers=operator_headers)

    assert javob.status_code == 201
    assert javob.json()["surat_yoli"] is not None
    sendphoto = [u for u, _ in yuborilgan if u.endswith("/sendPhoto")]
    assert len(sendphoto) == 1
    caption = yuborilgan[0][1]["caption"]
    assert "Mahsulot: Tola" in caption
    assert "Partiya: #301" in caption
    assert "Kip №" in caption
    assert "Og'irlik: 133.0 kg" in caption


def test_telegram_xatosi_kip_saqlashni_buzmaydi(
    client, db, operator_headers, mahsulot_tola, monkeypatch, tmp_path
):
    monkeypatch.setattr(settings, "STORAGE_PATH", str(tmp_path))
    monkeypatch.setattr(settings, "KAMERA_IP", "10.0.0.9")
    monkeypatch.setattr(settings, "KAMERA_LOGIN", "a")
    monkeypatch.setattr(settings, "KAMERA_PAROL", "b")
    monkeypatch.setattr("app.services.kamera.snapshot_ol", lambda: SOXTA_JPEG)
    db.add(Sozlama(kalit=telegram.SURAT_TOKEN_KALITI, qiymat="tok"))
    db.add(Sozlama(kalit=telegram.SURAT_CHAT_KALITI, qiymat="chat"))
    db.commit()
    monkeypatch.setattr(telegram.httpx, "post", lambda *a, **k: (_ for _ in ()).throw(httpx.ConnectError("x")))

    partiya = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": 302}, headers=operator_headers
    ).json()
    javob = client.post("/api/v1/kiplar", json=_payload(partiya["id"]), headers=operator_headers)

    assert javob.status_code == 201  # Telegram xatosi operatorni bloklamadi

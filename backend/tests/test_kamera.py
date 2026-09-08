"""IP kamera integratsiyasi testlari.

Hech bir test real tarmoqqa chiqmaydi — kamera chaqiruvi (httpx / snapshot_ol)
har doim mocklanadi.
"""

import uuid
from datetime import datetime, timezone

import httpx
import pytest

from app.core.config import settings
from app.models.kip import Kip
from app.services import kamera

# Minimal, lekin haqiqiy JPEG sarlavha/quyruq bilan "surat"
SOXTA_JPEG = b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01" + b"\x00" * 32 + b"\xff\xd9"


@pytest.fixture()
def kamera_sozlangan(monkeypatch, tmp_path):
    """Kamera .env qiymatlari + suratlar uchun vaqtinchalik STORAGE_PATH."""
    monkeypatch.setattr(settings, "KAMERA_IP", "10.0.0.9")
    monkeypatch.setattr(settings, "KAMERA_LOGIN", "admin")
    monkeypatch.setattr(settings, "KAMERA_PAROL", "sirli")
    monkeypatch.setattr(settings, "STORAGE_PATH", str(tmp_path))
    return tmp_path


def _payload(partiya_id: int, ogirlik: float = 133.0) -> dict:
    return {
        "mijoz_id": str(uuid.uuid4()),
        "partiya_id": partiya_id,
        "ogirlik": ogirlik,
        "mahalliy_vaqt": datetime.now(timezone.utc).isoformat(),
    }


def _partiya(client, operator_headers, raqam: int) -> dict:
    return client.post(
        "/api/v1/partiyalar",
        json={"mahsulot_kodi": "tola", "partiya_raqami": raqam},
        headers=operator_headers,
    ).json()


# --- Birlik testlari: kamera moduli ---


def test_snapshot_ol_sozlanmagan_bolsa_none(monkeypatch):
    monkeypatch.setattr(settings, "KAMERA_IP", None)
    assert kamera.sozlangan() is False
    assert kamera.snapshot_ol() is None


def test_snapshot_ol_muvaffaqiyatli(monkeypatch, kamera_sozlangan):
    chaqirilgan = {}

    def soxta_get(url, **kwargs):
        chaqirilgan["url"] = url
        chaqirilgan["auth"] = kwargs.get("auth")
        return httpx.Response(200, content=SOXTA_JPEG, request=httpx.Request("GET", url))

    monkeypatch.setattr(kamera.httpx, "get", soxta_get)

    baytlar = kamera.snapshot_ol()
    assert baytlar == SOXTA_JPEG
    assert chaqirilgan["url"] == "http://10.0.0.9/ISAPI/Streaming/channels/101/picture"
    assert isinstance(chaqirilgan["auth"], httpx.DigestAuth)


def test_snapshot_ol_tarmoq_xatosi_yutiladi(monkeypatch, kamera_sozlangan):
    def soxta_get(url, **kwargs):
        raise httpx.ConnectError("ulanib bo'lmadi")

    monkeypatch.setattr(kamera.httpx, "get", soxta_get)
    assert kamera.snapshot_ol() is None  # istisno tashqariga chiqmaydi


def test_snapshot_ol_http_500_yutiladi(monkeypatch, kamera_sozlangan):
    monkeypatch.setattr(
        kamera.httpx, "get", lambda url, **kw: httpx.Response(500, request=httpx.Request("GET", url))
    )
    assert kamera.snapshot_ol() is None


def test_kip_uchun_surat_saqla_fayl_yozadi(monkeypatch, kamera_sozlangan):
    monkeypatch.setattr(kamera, "snapshot_ol", lambda: SOXTA_JPEG)
    vaqt = datetime(2026, 9, 8, 10, 30, tzinfo=timezone.utc)

    nisbiy = kamera.kip_uchun_surat_saqla("Tola", "A", vaqt)

    assert nisbiy is not None
    # Yangi tuzilma: <Oy>/<Kun>/Smena_<X>/<Mahsulot nomi>/<fayl>
    assert nisbiy.startswith("2026-09/2026-09-08/Smena_A/Tola/")
    assert nisbiy.endswith(".jpg")
    assert (kamera_sozlangan / nisbiy).read_bytes() == SOXTA_JPEG


def test_kip_uchun_surat_saqla_snapshot_xatosi_none_qaytaradi(monkeypatch, kamera_sozlangan):
    def portlaydi():
        raise RuntimeError("kutilmagan")

    monkeypatch.setattr(kamera, "snapshot_ol", portlaydi)
    assert kamera.kip_uchun_surat_saqla("Tola", "A", datetime.now(timezone.utc)) is None


# --- Integratsiya: kip saqlash oqimi ---


def test_kip_saqlashda_kameradan_surat_olinadi(client, operator_headers, mahsulot_tola, monkeypatch, kamera_sozlangan):
    monkeypatch.setattr("app.services.kamera.snapshot_ol", lambda: SOXTA_JPEG)
    partiya = _partiya(client, operator_headers, 201)

    javob = client.post("/api/v1/kiplar", json=_payload(partiya["id"]), headers=operator_headers)

    assert javob.status_code == 201
    surat_yoli = javob.json()["surat_yoli"]
    assert surat_yoli is not None
    # mahsulot_tola: kod="tola", nomi="Tola" -> papka mahsulot NOMI bilan
    assert "/media/" in surat_yoli
    assert "/Smena_A/Tola/" in surat_yoli
    assert surat_yoli.endswith(".jpg")

    # Fayl haqiqatan diskka yozilgan
    nisbiy = surat_yoli.split("/media/", 1)[1]
    assert (kamera_sozlangan / nisbiy).read_bytes() == SOXTA_JPEG


def test_kamera_xato_bersa_kip_baribir_saqlanadi(client, operator_headers, mahsulot_tola, monkeypatch, kamera_sozlangan):
    def soxta_get(url, **kwargs):
        raise httpx.ConnectError("kamera o'chiq")

    monkeypatch.setattr("app.services.kamera.httpx.get", soxta_get)
    partiya = _partiya(client, operator_headers, 202)

    javob = client.post("/api/v1/kiplar", json=_payload(partiya["id"]), headers=operator_headers)

    assert javob.status_code == 201  # operator bloklanmadi
    assert javob.json()["surat_yoli"] is None


def test_kamera_sozlanmagan_bolsa_chaqirilmaydi(client, operator_headers, mahsulot_tola, monkeypatch):
    monkeypatch.setattr(settings, "KAMERA_IP", None)

    def portlaydi(*a, **kw):
        raise AssertionError("kamera sozlanmagan bo'lsa chaqirilmasligi kerak")

    monkeypatch.setattr("app.services.kamera.snapshot_ol", portlaydi)
    partiya = _partiya(client, operator_headers, 203)

    javob = client.post("/api/v1/kiplar", json=_payload(partiya["id"]), headers=operator_headers)

    assert javob.status_code == 201
    assert javob.json()["surat_yoli"] is None


def test_mijoz_bergan_surat_yoli_kamera_bilan_almashtirilmaydi(
    client, operator_headers, mahsulot_tola, monkeypatch, kamera_sozlangan
):
    monkeypatch.setattr(
        "app.services.kamera.snapshot_ol",
        lambda: (_ for _ in ()).throw(AssertionError("mijoz suratni bergan — kamera chaqirilmasin")),
    )
    partiya = _partiya(client, operator_headers, 204)
    payload = _payload(partiya["id"])
    payload["surat_yoli"] = "tola/2026-09/2026-09-08/A/mavjud.jpg"

    javob = client.post("/api/v1/kiplar", json=payload, headers=operator_headers)

    assert javob.status_code == 201
    assert javob.json()["surat_yoli"].endswith("/media/tola/2026-09/2026-09-08/A/mavjud.jpg")

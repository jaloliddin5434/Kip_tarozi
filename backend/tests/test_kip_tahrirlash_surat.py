"""0-QISM audit natijasi (bug fix): PATCH /kiplar/{id} orqali mahsulot
o'zgartirilsa, mavjud surat fayli TO'G'RI (yangi mahsulot) papkasiga
ko'chishi kerak — avval bu qilinmasdi (surat diskda eski, endi noto'g'ri
bo'lgan papkada qolib ketardi). Partiya raqami o'zgarib, mahsulot bir xil
qolsa — surat papkasi (u faqat mahsulot nomiga bog'liq) umuman
ko'chmasligi kerak."""

import uuid
from datetime import datetime, timezone
from pathlib import Path

import httpx
import pytest
from sqlalchemy import select

from app.core.config import settings
from app.models.kip import Kip
from app.models.mahsulot import Mahsulot
from app.models.partiya import Partiya, PartiyaHolati
from app.models.sozlama import Sozlama
from app.services import telegram
from app.services.storage.rasm import rasm_saqla

BAYT = b"\xff\xd8\xff\xe0test\xff\xd9"
VAQT = datetime(2026, 9, 10, 10, 0, tzinfo=timezone.utc)


@pytest.fixture(autouse=True)
def _storage(monkeypatch, tmp_path):
    monkeypatch.setattr(settings, "STORAGE_PATH", str(tmp_path))
    return tmp_path


@pytest.fixture()
def mahsulot_lint(db) -> Mahsulot:
    mahsulot = Mahsulot(kod="lint", nomi="Lint")
    db.add(mahsulot)
    db.commit()
    db.refresh(mahsulot)
    return mahsulot


def _partiya_yarat(db, mahsulot_id: int, raqami: int) -> Partiya:
    partiya = Partiya(mahsulot_id=mahsulot_id, partiya_raqami=raqami, holati=PartiyaHolati.ochiq)
    db.add(partiya)
    db.commit()
    db.refresh(partiya)
    return partiya


def _kip_yarat_suratli(client, operator_headers, partiya_id: int, mahsulot_nomi: str) -> dict:
    """Kipni API orqali yaratadi (kamera o'chirilgan — surat_yoli mijoz
    tomonidan berilgan deb hisoblanadi), diskda ham HAQIQIY surat fayli bilan
    (rasm_saqla orqali), xuddi haqiqiy kamera olib bergandek."""
    nisbiy_yol = rasm_saqla(BAYT, smena="A", vaqt=VAQT, turi="kip", mahsulot_nomi=mahsulot_nomi)
    javob = client.post(
        "/api/v1/kiplar",
        json={
            "mijoz_id": str(uuid.uuid4()),
            "partiya_id": partiya_id,
            "ogirlik": 150.0,
            "mahalliy_vaqt": VAQT.isoformat(),
            "surat_yoli": nisbiy_yol,
        },
        headers=operator_headers,
    )
    assert javob.status_code == 201, javob.text
    return javob.json()


def test_mahsulot_ozgarsa_surat_yangi_papkaga_kochadi(
    client, db, admin_headers, operator_headers, mahsulot_tola, mahsulot_lint
):
    eski_partiya = _partiya_yarat(db, mahsulot_tola.id, 401)
    yangi_partiya = _partiya_yarat(db, mahsulot_lint.id, 402)

    kip = _kip_yarat_suratli(client, operator_headers, eski_partiya.id, "Tola")
    eski_surat_yoli = kip["surat_yoli"]
    assert "/Tola/" in eski_surat_yoli
    eski_fayl = _storage_fayl(eski_surat_yoli)
    assert eski_fayl.is_file()

    javob = client.patch(
        f"/api/v1/kiplar/{kip['id']}",
        json={"mahsulot_kodi": "lint", "partiya_raqami": 402, "sabab": "Noto'g'ri mahsulot tanlangan edi"},
        headers=admin_headers,
    )
    assert javob.status_code == 200, javob.text
    yangi_surat_yoli = javob.json()["surat_yoli"]

    assert "/Lint/" in yangi_surat_yoli
    assert yangi_surat_yoli != eski_surat_yoli
    assert not eski_fayl.is_file(), "eski fayl diskda qolib ketmasligi kerak"
    assert _storage_fayl(yangi_surat_yoli).read_bytes() == BAYT

    db_kip_surat_yoli = db.execute(select(Kip.surat_yoli).where(Kip.id == kip["id"])).scalar_one()
    assert "Lint" in db_kip_surat_yoli


def test_partiya_ozgarib_mahsulot_bir_xil_qolsa_surat_kochmaydi(
    client, db, admin_headers, operator_headers, mahsulot_tola
):
    partiya_1 = _partiya_yarat(db, mahsulot_tola.id, 403)
    partiya_2 = _partiya_yarat(db, mahsulot_tola.id, 404)

    kip = _kip_yarat_suratli(client, operator_headers, partiya_1.id, "Tola")
    eski_surat_yoli = kip["surat_yoli"]

    javob = client.patch(
        f"/api/v1/kiplar/{kip['id']}",
        json={"mahsulot_kodi": "tola", "partiya_raqami": 404, "sabab": "Partiya raqami xato kiritilgan edi"},
        headers=admin_headers,
    )
    assert javob.status_code == 200, javob.text

    # PATCH javobidagi surat_yoli hozircha /media/ URL emas, xom nisbiy yo'l
    # (POST/GET-batafsil bilan formatda nomuvofiqlik — bu audit doirasidan
    # tashqari, alohida masala) — shuning uchun disk yo'li orqali solishtiramiz.
    assert _storage_fayl(javob.json()["surat_yoli"]) == _storage_fayl(eski_surat_yoli)
    assert _storage_fayl(eski_surat_yoli).is_file()


# --- 1-QISM: mahsulot o'zgarganda ESKI Telegram surat xabari yangilanishi ---


@pytest.fixture()
def surat_boti_sozlangan(db):
    db.add(Sozlama(kalit=telegram.SURAT_TOKEN_KALITI, qiymat="123:ABC"))
    db.add(Sozlama(kalit=telegram.SURAT_CHAT_KALITI, qiymat="999"))
    db.commit()


def _kip_yarat_suratli_telegram_bilan(
    client, db, operator_headers, partiya_id: int, mahsulot_nomi: str, monkeypatch
) -> dict:
    """`_kip_yarat_suratli` bilan bir xil, lekin surat_yubor() ham chaqiriladi
    (mocklangan, message_id=777 qaytaradi) — kip.telegram_surat_xabar_id
    to'ldirilgan holatda yaratiladi."""
    monkeypatch.setattr(
        telegram.httpx,
        "post",
        lambda url, **kw: httpx.Response(200, json={"ok": True, "result": {"message_id": 777}}, request=httpx.Request("POST", url)),
    )
    kip = _kip_yarat_suratli(client, operator_headers, partiya_id, mahsulot_nomi)
    db_kip = db.get(Kip, kip["id"])
    assert db_kip.telegram_surat_xabar_id == 777
    return kip


def test_mahsulot_ozgarsa_telegram_surat_xabari_yangilanadi(
    client, db, admin_headers, operator_headers, mahsulot_tola, mahsulot_lint, surat_boti_sozlangan, monkeypatch
):
    eski_partiya = _partiya_yarat(db, mahsulot_tola.id, 410)
    yangi_partiya = _partiya_yarat(db, mahsulot_lint.id, 411)
    kip = _kip_yarat_suratli_telegram_bilan(client, db, operator_headers, eski_partiya.id, "Tola", monkeypatch)

    chaqiruvlar = []

    def soxta_post(url, **kw):
        chaqiruvlar.append((url, kw.get("json")))
        return httpx.Response(200, json={"ok": True}, request=httpx.Request("POST", url))

    monkeypatch.setattr(telegram.httpx, "post", soxta_post)

    javob = client.patch(
        f"/api/v1/kiplar/{kip['id']}",
        json={"mahsulot_kodi": "lint", "partiya_raqami": 411, "sabab": "Noto'g'ri mahsulot tanlangan edi"},
        headers=admin_headers,
    )
    assert javob.status_code == 200, javob.text

    edit_chaqiruvlari = [c for c in chaqiruvlar if c[0].endswith("/editMessageCaption")]
    assert len(edit_chaqiruvlari) == 1
    tana = edit_chaqiruvlari[0][1]
    assert tana["chat_id"] == "999"
    assert tana["message_id"] == 777
    assert "🔄 Tuzatildi:" in tana["caption"]
    assert "Mahsulot: Lint" in tana["caption"]
    assert f"Partiya: #{yangi_partiya.partiya_raqami}" in tana["caption"]


def test_faqat_partiya_ozgarsa_telegram_xabar_yangilanmaydi(
    client, db, admin_headers, operator_headers, mahsulot_tola, surat_boti_sozlangan, monkeypatch
):
    """Mahsulot bir xil qolsa (faqat partiya raqami o'zgarsa) — Telegram
    xabarini yangilashning hojati yo'q, chaqirilmasligi kerak."""
    partiya_1 = _partiya_yarat(db, mahsulot_tola.id, 412)
    partiya_2 = _partiya_yarat(db, mahsulot_tola.id, 413)
    kip = _kip_yarat_suratli_telegram_bilan(client, db, operator_headers, partiya_1.id, "Tola", monkeypatch)

    monkeypatch.setattr(
        telegram.httpx, "post", lambda *a, **k: (_ for _ in ()).throw(AssertionError("chaqirilmasligi kerak"))
    )

    javob = client.patch(
        f"/api/v1/kiplar/{kip['id']}",
        json={"mahsulot_kodi": "tola", "partiya_raqami": 413, "sabab": "Partiya raqami xato kiritilgan edi"},
        headers=admin_headers,
    )
    assert javob.status_code == 200, javob.text


def test_telegram_xabar_id_yoq_bolsa_yangilash_urinilmaydi(
    client, db, admin_headers, operator_headers, mahsulot_tola, mahsulot_lint, surat_boti_sozlangan, monkeypatch
):
    """Kipda telegram_surat_xabar_id yo'q bo'lsa (masalan surat_yubor()
    muvaffaqiyatsiz bo'lgan edi) — editMessageCaption umuman chaqirilmasin."""
    eski_partiya = _partiya_yarat(db, mahsulot_tola.id, 414)
    yangi_partiya = _partiya_yarat(db, mahsulot_lint.id, 415)
    kip = _kip_yarat_suratli(client, operator_headers, eski_partiya.id, "Tola")
    assert db.get(Kip, kip["id"]).telegram_surat_xabar_id is None

    monkeypatch.setattr(
        telegram.httpx, "post", lambda *a, **k: (_ for _ in ()).throw(AssertionError("chaqirilmasligi kerak"))
    )

    javob = client.patch(
        f"/api/v1/kiplar/{kip['id']}",
        json={"mahsulot_kodi": "lint", "partiya_raqami": 415, "sabab": "Noto'g'ri mahsulot tanlangan edi"},
        headers=admin_headers,
    )
    assert javob.status_code == 200, javob.text


def test_telegram_xatosi_tahrirlashni_buzmaydi(
    client, db, admin_headers, operator_headers, mahsulot_tola, mahsulot_lint, surat_boti_sozlangan, monkeypatch
):
    eski_partiya = _partiya_yarat(db, mahsulot_tola.id, 416)
    yangi_partiya = _partiya_yarat(db, mahsulot_lint.id, 417)
    kip = _kip_yarat_suratli_telegram_bilan(client, db, operator_headers, eski_partiya.id, "Tola", monkeypatch)

    monkeypatch.setattr(telegram.httpx, "post", lambda *a, **k: (_ for _ in ()).throw(httpx.ConnectError("x")))

    javob = client.patch(
        f"/api/v1/kiplar/{kip['id']}",
        json={"mahsulot_kodi": "lint", "partiya_raqami": 417, "sabab": "Noto'g'ri mahsulot tanlangan edi"},
        headers=admin_headers,
    )
    assert javob.status_code == 200, javob.text  # Telegram xatosi tahrirlashni bloklamadi


def _storage_fayl(ommaviy_url_yoki_nisbiy_yol: str) -> Path:
    """API javobi surat_yoli'ni to'liq /media/ URL qilib qaytaradi
    (surat_ommaviy_url) — diskdagi haqiqiy faylni topish uchun shu URL'dan
    STORAGE_PATH'ga nisbiy qismini ajratib olamiz."""
    nisbiy_yol = ommaviy_url_yoki_nisbiy_yol.split("/media/", 1)[-1]
    return Path(settings.STORAGE_PATH) / nisbiy_yol

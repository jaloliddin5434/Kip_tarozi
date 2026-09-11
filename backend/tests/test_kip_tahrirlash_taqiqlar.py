"""Ikkinchi eshelon audit topilmalari — 1/2/4-QISM:

1-QISM: bekor qilingan kipni tahrirlash/tasdiqlash RAD ETILISHI kerak
        (PATCH /kiplar/{id} HAM, POST /kip-togrilash yaratish/tasdiqlash HAM).
2-QISM: sotilgan partiyaga kip ko'chirish RAD ETILISHI kerak (xuddi shu
        ikkala oqimda).
4-QISM: mahsulot o'zgarganda Telegram "surat boti" xabarini yangilash
        so'rovi DB COMMIT'dan KEYIN yuborilishi kerak (partiya qatori
        qulflangan holda emas).
"""

import uuid
from datetime import datetime, timezone

import httpx
import pytest

from app.models.kip import Kip, KipHolati
from app.models.mahsulot import Mahsulot
from app.models.partiya import Partiya, PartiyaHolati
from app.models.sozlama import Sozlama
from app.services import telegram

VAQT = datetime(2026, 9, 10, 10, 0, tzinfo=timezone.utc)


def _partiya(db, mahsulot_id: int, raqami: int, holati: PartiyaHolati = PartiyaHolati.ochiq) -> Partiya:
    p = Partiya(mahsulot_id=mahsulot_id, partiya_raqami=raqami, holati=holati)
    db.add(p)
    db.commit()
    db.refresh(p)
    return p


def _kip_yarat(client, operator_headers, partiya_id: int) -> dict:
    javob = client.post(
        "/api/v1/kiplar",
        json={
            "mijoz_id": str(uuid.uuid4()),
            "partiya_id": partiya_id,
            "ogirlik": 100.0,
            "mahalliy_vaqt": VAQT.isoformat(),
        },
        headers=operator_headers,
    )
    assert javob.status_code == 201, javob.text
    return javob.json()


@pytest.fixture()
def mahsulot_lint(db) -> Mahsulot:
    m = Mahsulot(kod="lint", nomi="Lint")
    db.add(m)
    db.commit()
    db.refresh(m)
    return m


# --------------------------------------------------------------------------
# 1-QISM: bekor qilingan kip
# --------------------------------------------------------------------------


def test_bekor_qilingan_kipni_patch_bilan_tahrirlab_bolmaydi(client, db, admin_headers, operator_headers, mahsulot_tola, mahsulot_lint):
    p1 = _partiya(db, mahsulot_tola.id, 501)
    p2 = _partiya(db, mahsulot_lint.id, 502)
    kip = _kip_yarat(client, operator_headers, p1.id)

    javob = client.request("DELETE", f"/api/v1/kiplar/{kip['id']}", json={"sabab": "test uchun bekor qilindi"}, headers=admin_headers)
    assert javob.status_code == 200, javob.text
    assert db.get(Kip, kip["id"]).holati == KipHolati.bekor_qilingan

    javob2 = client.patch(
        f"/api/v1/kiplar/{kip['id']}",
        json={"mahsulot_kodi": "lint", "partiya_raqami": 502, "sabab": "urinish"},
        headers=admin_headers,
    )
    assert javob2.status_code == 409, javob2.text
    assert "bekor qilingan" in javob2.json()["detail"].lower()

    # Kip HAQIQATAN o'zgarmagan bo'lishi kerak
    db.expire_all()
    db_kip = db.get(Kip, kip["id"])
    assert db_kip.partiya_id == p1.id
    assert db_kip.holati == KipHolati.bekor_qilingan


def test_bekor_qilingan_kip_uchun_togrilash_zayavkasi_yaratilmaydi(client, db, admin_headers, operator_headers, mahsulot_tola, mahsulot_lint):
    p1 = _partiya(db, mahsulot_tola.id, 503)
    p2 = _partiya(db, mahsulot_lint.id, 504)
    kip = _kip_yarat(client, operator_headers, p1.id)
    client.request("DELETE", f"/api/v1/kiplar/{kip['id']}", json={"sabab": "test"}, headers=admin_headers)

    javob = client.post(
        "/api/v1/kip-togrilash",
        json={"kip_id": kip["id"], "yangi_mahsulot_kodi": "lint", "yangi_partiya_raqami": 504, "sabab": "xato"},
        headers=operator_headers,
    )
    assert javob.status_code == 409, javob.text
    assert "bekor qilingan" in javob.json()["detail"].lower()


def test_zayavka_yaratilgandan_keyin_kip_bekor_qilinsa_tasdiqlash_rad_etiladi(
    client, db, admin_headers, operator_headers, mahsulot_tola, mahsulot_lint
):
    """Zayavka YARATILGAN paytda kip aktiv edi, lekin ADMIN TASDIQLASHDAN
    OLDIN kimdir kipni bekor qilib ulgurdi — tasdiqlash ham rad etilishi
    kerak (idempotent: zayavka 'kutilmoqda' holatida qolib ketishi kerak,
    keyinroq to'g'ri hal qilish uchun)."""
    p1 = _partiya(db, mahsulot_tola.id, 505)
    p2 = _partiya(db, mahsulot_lint.id, 506)
    kip = _kip_yarat(client, operator_headers, p1.id)

    javob = client.post(
        "/api/v1/kip-togrilash",
        json={"kip_id": kip["id"], "yangi_mahsulot_kodi": "lint", "yangi_partiya_raqami": 506, "sabab": "xato"},
        headers=operator_headers,
    )
    assert javob.status_code == 201, javob.text
    zayavka_id = javob.json()["id"]

    client.request("DELETE", f"/api/v1/kiplar/{kip['id']}", json={"sabab": "keyinroq bekor qilindi"}, headers=admin_headers)

    javob2 = client.post(f"/api/v1/kip-togrilash/{zayavka_id}/tasdiqlash", headers=admin_headers)
    assert javob2.status_code == 409, javob2.text

    # Zayavka hali "kutilmoqda" holatida qolishi kerak (o'zgarmagan)
    royxat = client.get("/api/v1/kip-togrilash", headers=admin_headers).json()
    item = next(i for i in royxat["items"] if i["id"] == zayavka_id)
    assert item["holati"] == "kutilmoqda"


# --------------------------------------------------------------------------
# 2-QISM: sotilgan partiya
# --------------------------------------------------------------------------


def test_sotilgan_partiyaga_kip_patch_bilan_kochirib_bolmaydi(client, db, admin_headers, operator_headers, mahsulot_tola, mahsulot_lint):
    p1 = _partiya(db, mahsulot_tola.id, 507)
    p2 = _partiya(db, mahsulot_lint.id, 508, holati=PartiyaHolati.sotilgan)
    kip = _kip_yarat(client, operator_headers, p1.id)

    javob = client.patch(
        f"/api/v1/kiplar/{kip['id']}",
        json={"mahsulot_kodi": "lint", "partiya_raqami": 508, "sabab": "urinish"},
        headers=admin_headers,
    )
    assert javob.status_code == 409, javob.text
    assert "sotilgan" in javob.json()["detail"].lower()

    db.expire_all()
    assert db.get(Kip, kip["id"]).partiya_id == p1.id


def test_sotilgan_partiyaga_togrilash_zayavkasi_yaratilmaydi(client, db, admin_headers, operator_headers, mahsulot_tola, mahsulot_lint):
    p1 = _partiya(db, mahsulot_tola.id, 509)
    p2 = _partiya(db, mahsulot_lint.id, 510, holati=PartiyaHolati.sotilgan)
    kip = _kip_yarat(client, operator_headers, p1.id)

    javob = client.post(
        "/api/v1/kip-togrilash",
        json={"kip_id": kip["id"], "yangi_mahsulot_kodi": "lint", "yangi_partiya_raqami": 510, "sabab": "xato"},
        headers=operator_headers,
    )
    assert javob.status_code == 409, javob.text
    assert "sotilgan" in javob.json()["detail"].lower()


def test_zayavka_yaratilgandan_keyin_partiya_sotilsa_tasdiqlash_rad_etiladi(
    client, db, admin_headers, operator_headers, mahsulot_tola, mahsulot_lint
):
    p1 = _partiya(db, mahsulot_tola.id, 511)
    p2 = _partiya(db, mahsulot_lint.id, 512)
    kip = _kip_yarat(client, operator_headers, p1.id)

    javob = client.post(
        "/api/v1/kip-togrilash",
        json={"kip_id": kip["id"], "yangi_mahsulot_kodi": "lint", "yangi_partiya_raqami": 512, "sabab": "xato"},
        headers=operator_headers,
    )
    assert javob.status_code == 201, javob.text
    zayavka_id = javob.json()["id"]

    # Endi (zayavka yaratilgandan keyin) maqsad partiya sotilib ketdi
    p2_db = db.get(Partiya, p2.id)
    p2_db.holati = PartiyaHolati.sotilgan
    db.commit()

    javob2 = client.post(f"/api/v1/kip-togrilash/{zayavka_id}/tasdiqlash", headers=admin_headers)
    assert javob2.status_code == 409, javob2.text
    assert "sotilgan" in javob2.json()["detail"].lower()


# --------------------------------------------------------------------------
# 4-QISM: Telegram so'rovi COMMIT'dan KEYIN
# --------------------------------------------------------------------------


@pytest.fixture()
def surat_boti_sozlangan(db):
    db.add(Sozlama(kalit=telegram.SURAT_TOKEN_KALITI, qiymat="123:ABC"))
    db.add(Sozlama(kalit=telegram.SURAT_CHAT_KALITI, qiymat="999"))
    db.commit()


def test_telegram_sorovi_commitdan_keyin_yuboriladi(
    client, db, admin_headers, operator_headers, mahsulot_tola, mahsulot_lint, surat_boti_sozlangan, monkeypatch, tmp_path
):
    """4-QISM (audit topilmasi): oldin Telegram so'rovi hali DB tranzaksiyasi
    (partiya qatori qulflangan) ICHIDA chaqirilardi. Endi `db.commit()`dan
    KEYIN chaqirilishi kerak — bu testda chaqiruvlar TARTIBINI kuzatib
    tasdiqlaymiz."""
    from app.core.config import settings
    from app.models.kip import Kip as KipModel
    from app.services.storage.rasm import rasm_saqla

    monkeypatch.setattr(settings, "STORAGE_PATH", str(tmp_path))
    monkeypatch.setattr(
        telegram.httpx,
        "post",
        lambda url, **kw: httpx.Response(200, json={"ok": True, "result": {"message_id": 777}}, request=httpx.Request("POST", url)),
    )
    p1 = _partiya(db, mahsulot_tola.id, 513)
    p2 = _partiya(db, mahsulot_lint.id, 514)
    nisbiy_yol = rasm_saqla(b"\xff\xd8\xff\xe0test\xff\xd9", smena="A", vaqt=VAQT, turi="kip", mahsulot_nomi="Tola")
    kip = client.post(
        "/api/v1/kiplar",
        json={
            "mijoz_id": str(uuid.uuid4()),
            "partiya_id": p1.id,
            "ogirlik": 150.0,
            "mahalliy_vaqt": VAQT.isoformat(),
            "surat_yoli": nisbiy_yol,
        },
        headers=operator_headers,
    ).json()
    assert db.get(KipModel, kip["id"]).telegram_surat_xabar_id == 777

    tartib: list[str] = []
    haqiqiy_commit = db.commit

    def kuzatuvchi_commit():
        tartib.append("commit")
        return haqiqiy_commit()

    monkeypatch.setattr(db, "commit", kuzatuvchi_commit)

    def soxta_post(url, **kw):
        tartib.append("telegram")
        return httpx.Response(200, json={"ok": True}, request=httpx.Request("POST", url))

    monkeypatch.setattr(telegram.httpx, "post", soxta_post)

    javob = client.patch(
        f"/api/v1/kiplar/{kip['id']}",
        json={"mahsulot_kodi": "lint", "partiya_raqami": 514, "sabab": "Noto'g'ri mahsulot tanlangan edi"},
        headers=admin_headers,
    )
    assert javob.status_code == 200, javob.text

    assert "telegram" in tartib, f"Telegram so'rovi umuman chaqirilmadi: {tartib}"
    oxirgi_commit_indeksi = max(i for i, x in enumerate(tartib) if x == "commit")
    telegram_indeksi = tartib.index("telegram")
    assert telegram_indeksi > oxirgi_commit_indeksi, (
        f"Telegram so'rovi COMMIT'dan OLDIN chaqirilgan (tartib: {tartib}) — "
        "bu partiya qatorini keraksiz uzoq qulflab turadi"
    )

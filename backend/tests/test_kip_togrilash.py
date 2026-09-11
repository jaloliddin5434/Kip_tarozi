"""Kip to'g'rilash zayavkasi oqimi — kamera_tasdiq.py testlari bilan bir xil
naqsh. Hech bir test real Telegramga chiqmaydi (xatolik_xabari_tugma_bilan
mock qilinadi)."""

import uuid
from datetime import datetime, timezone

import pytest

from app.core.config import settings
from app.models.foydalanuvchi import Foydalanuvchi, Rol, Smena
from app.models.kip import Kip
from app.models.kip_togrilash import KipTogrilashHolati, KipTogrilashZayavkasi
from app.models.mahsulot import Mahsulot
from app.models.partiya import Partiya, PartiyaHolati


@pytest.fixture(autouse=True)
def _telegram_jim(monkeypatch):
    yuborilgan = []
    monkeypatch.setattr(
        "app.api.v1.routes.kip_togrilash.xatolik_xabari_tugma_bilan",
        lambda db, matn, **kw: yuborilgan.append(matn),
    )
    return yuborilgan


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


@pytest.fixture()
def operator_b_headers(db):
    from app.core.security import parolni_hash, token_yarat

    op_b = Foydalanuvchi(
        ism="Smena B", login="smena_b_kt", parol_hash=parolni_hash("parolB"), rol=Rol.operator, smena=Smena.B
    )
    db.add(op_b)
    db.commit()
    db.refresh(op_b)
    token = token_yarat({"sub": str(op_b.id), "rol": "operator", "smena": "B", "tv": op_b.token_versiyasi})
    return {"Authorization": f"Bearer {token}"}


def _partiya_yarat(db, mahsulot_id: int, raqami: int) -> Partiya:
    partiya = Partiya(mahsulot_id=mahsulot_id, partiya_raqami=raqami, holati=PartiyaHolati.ochiq)
    db.add(partiya)
    db.commit()
    db.refresh(partiya)
    return partiya


def _kip_yarat(db, operator, partiya, ogirlik=145.0, surat_yoli=None) -> Kip:
    vaqt = datetime(2026, 9, 10, 9, 0, tzinfo=timezone.utc)
    kip = Kip(
        mijoz_id=str(uuid.uuid4()),
        partiya_id=partiya.id,
        kip_raqami=1,
        ogirlik=ogirlik,
        smena=operator.smena,
        operator_id=operator.id,
        mahalliy_vaqt=vaqt,
        vaqt=vaqt,
        surat_yoli=surat_yoli,
    )
    db.add(kip)
    db.commit()
    db.refresh(kip)
    return kip


def _payload(kip_id: int, yangi_mahsulot_kodi="lint", yangi_partiya_raqami=502, sabab="Noto'g'ri mahsulot tanlandi"):
    return {
        "kip_id": kip_id,
        "yangi_mahsulot_kodi": yangi_mahsulot_kodi,
        "yangi_partiya_raqami": yangi_partiya_raqami,
        "sabab": sabab,
    }


# --- POST /kip-togrilash ---


def test_zayavka_yaratish_ishlaydi(client, db, operator, operator_headers, mahsulot_tola, mahsulot_lint, _telegram_jim):
    eski_partiya = _partiya_yarat(db, mahsulot_tola.id, 501)
    yangi_partiya = _partiya_yarat(db, mahsulot_lint.id, 502)
    kip = _kip_yarat(db, operator, eski_partiya)

    javob = client.post("/api/v1/kip-togrilash", json=_payload(kip.id), headers=operator_headers)

    assert javob.status_code == 201, javob.text
    tana = javob.json()
    assert tana["holati"] == "kutilmoqda"

    zayavka = db.get(KipTogrilashZayavkasi, tana["id"])
    assert zayavka.kip_id == kip.id
    assert zayavka.eski_mahsulot_id == mahsulot_tola.id
    assert zayavka.eski_partiya_id == eski_partiya.id
    assert zayavka.yangi_mahsulot_id == mahsulot_lint.id
    assert zayavka.yangi_partiya_id == yangi_partiya.id
    assert zayavka.holati == KipTogrilashHolati.kutilmoqda

    assert any("KIP TO'G'RILASH SO'RALDI" in m for m in _telegram_jim)


def test_boshqa_smenadagi_kip_uchun_403(client, db, operator, operator_b_headers, mahsulot_tola, mahsulot_lint):
    eski_partiya = _partiya_yarat(db, mahsulot_tola.id, 503)
    _partiya_yarat(db, mahsulot_lint.id, 504)
    kip = _kip_yarat(db, operator, eski_partiya)  # operator (smena A) yaratgan

    javob = client.post("/api/v1/kip-togrilash", json=_payload(kip.id, yangi_partiya_raqami=504), headers=operator_b_headers)
    assert javob.status_code == 403


def test_notogri_mahsulot_kodi_400(client, db, operator, operator_headers, mahsulot_tola):
    partiya = _partiya_yarat(db, mahsulot_tola.id, 505)
    kip = _kip_yarat(db, operator, partiya)

    javob = client.post(
        "/api/v1/kip-togrilash",
        json=_payload(kip.id, yangi_mahsulot_kodi="yoq_mahsulot", yangi_partiya_raqami=1),
        headers=operator_headers,
    )
    assert javob.status_code == 400


def test_kip_topilmasa_404(client, operator_headers, mahsulot_tola):
    javob = client.post("/api/v1/kip-togrilash", json=_payload(999999), headers=operator_headers)
    assert javob.status_code == 404


# --- GET /kip-togrilash ---


def test_royxat_admin_koradi_operator_403(client, db, operator, operator_headers, admin_headers, mahsulot_tola, mahsulot_lint):
    eski_partiya = _partiya_yarat(db, mahsulot_tola.id, 506)
    _partiya_yarat(db, mahsulot_lint.id, 507)
    kip = _kip_yarat(db, operator, eski_partiya)
    client.post("/api/v1/kip-togrilash", json=_payload(kip.id, yangi_partiya_raqami=507), headers=operator_headers)

    assert client.get("/api/v1/kip-togrilash", headers=operator_headers).status_code == 403

    javob = client.get("/api/v1/kip-togrilash", params={"holati": "kutilmoqda"}, headers=admin_headers)
    assert javob.status_code == 200
    data = javob.json()
    assert data["jami"] >= 1
    yozuv = data["items"][0]
    assert yozuv["eski_mahsulot_nomi"] == "Tola"
    assert yozuv["eski_partiya_raqami"] == 506
    assert yozuv["yangi_mahsulot_nomi"] == "Lint"
    assert yozuv["yangi_partiya_raqami"] == 507
    assert yozuv["operator_ism"]
    assert yozuv["holati"] == "kutilmoqda"


# --- POST /kip-togrilash/{id}/tasdiqlash ---


def test_tasdiqlash_kipni_yangilaydi(client, db, operator, operator_headers, admin_headers, mahsulot_tola, mahsulot_lint, _storage):
    from app.services.storage.rasm import rasm_saqla

    eski_partiya = _partiya_yarat(db, mahsulot_tola.id, 508)
    yangi_partiya = _partiya_yarat(db, mahsulot_lint.id, 509)
    surat_yoli = rasm_saqla(b"jpeg", smena="A", vaqt=datetime(2026, 9, 10, 9, 0, tzinfo=timezone.utc), turi="kip", mahsulot_nomi="Tola")
    kip = _kip_yarat(db, operator, eski_partiya, surat_yoli=surat_yoli)

    zayavka_id = client.post(
        "/api/v1/kip-togrilash", json=_payload(kip.id, yangi_partiya_raqami=509), headers=operator_headers
    ).json()["id"]

    javob = client.post(f"/api/v1/kip-togrilash/{zayavka_id}/tasdiqlash", headers=admin_headers)
    assert javob.status_code == 200, javob.text
    assert javob.json()["holati"] == "tasdiqlangan"

    db.refresh(kip)
    assert kip.partiya_id == yangi_partiya.id
    assert kip.holati.value == "tahrirlangan"
    assert "/Lint/" in kip.surat_yoli
    assert (_storage / kip.surat_yoli).is_file()


def test_tasdiqlash_telegram_surat_xabarini_ham_yangilaydi(
    client, db, operator, operator_headers, admin_headers, mahsulot_tola, mahsulot_lint, monkeypatch
):
    """1-QISM: zayavka tasdiqlanganda ham (PATCH bilan bir xil kipni_tahrir_qil()
    orqali) mahsulot haqiqatan o'zgarsa va telegram_surat_xabar_id mavjud
    bo'lsa — ESKI Telegram xabarining caption'i yangilanishi kerak."""
    import httpx

    from app.models.sozlama import Sozlama
    from app.services import telegram

    db.add(Sozlama(kalit=telegram.SURAT_TOKEN_KALITI, qiymat="123:ABC"))
    db.add(Sozlama(kalit=telegram.SURAT_CHAT_KALITI, qiymat="999"))
    db.commit()

    eski_partiya = _partiya_yarat(db, mahsulot_tola.id, 530)
    yangi_partiya = _partiya_yarat(db, mahsulot_lint.id, 531)
    kip = _kip_yarat(db, operator, eski_partiya)
    kip.telegram_surat_xabar_id = 888
    db.commit()

    zayavka_id = client.post(
        "/api/v1/kip-togrilash", json=_payload(kip.id, yangi_partiya_raqami=531), headers=operator_headers
    ).json()["id"]

    chaqiruvlar = []
    monkeypatch.setattr(
        telegram.httpx,
        "post",
        lambda url, **kw: chaqiruvlar.append((url, kw.get("json")))
        or httpx.Response(200, json={"ok": True}, request=httpx.Request("POST", url)),
    )

    javob = client.post(f"/api/v1/kip-togrilash/{zayavka_id}/tasdiqlash", headers=admin_headers)
    assert javob.status_code == 200, javob.text

    edit_chaqiruvlari = [c for c in chaqiruvlar if c[0].endswith("/editMessageCaption")]
    assert len(edit_chaqiruvlari) == 1
    assert edit_chaqiruvlari[0][1]["message_id"] == 888
    assert "Mahsulot: Lint" in edit_chaqiruvlari[0][1]["caption"]


def test_tasdiqlash_yangi_partiyada_kip_raqami_bandligini_hal_qiladi(
    client, db, operator, operator_headers, admin_headers, mahsulot_tola, mahsulot_lint
):
    """Regressiya: ko'chirilayotgan kipning eski kip_raqami YANGI partiyada
    allaqachon band bo'lsa (masalan ikkalasida ham "#1"-kip bo'lsa),
    tasdiqlash uq_kip_partiya_raqam cheklovini buzib 500 bermasligi kerak —
    kip yangi partiyadagi navbatdagi bo'sh raqamni olishi kerak."""
    eski_partiya = _partiya_yarat(db, mahsulot_tola.id, 520)
    yangi_partiya = _partiya_yarat(db, mahsulot_lint.id, 521)

    # Yangi partiyada ALLAQACHON "#1"-kip bor (boshqa kip) — ko'chirilayotgan
    # kip ham xuddi shu raqamda (_kip_yarat standart kip_raqami=1 beradi).
    _kip_yarat(db, operator, yangi_partiya, ogirlik=50.0)
    kip = _kip_yarat(db, operator, eski_partiya, ogirlik=145.0)
    assert kip.kip_raqami == 1

    zayavka_id = client.post(
        "/api/v1/kip-togrilash", json=_payload(kip.id, yangi_partiya_raqami=521), headers=operator_headers
    ).json()["id"]

    javob = client.post(f"/api/v1/kip-togrilash/{zayavka_id}/tasdiqlash", headers=admin_headers)
    assert javob.status_code == 200, javob.text
    assert javob.json()["holati"] == "tasdiqlangan"

    db.refresh(kip)
    assert kip.partiya_id == yangi_partiya.id
    assert kip.kip_raqami == 2  # band bo'lgan "1"dan keyingi bo'sh raqam
    assert kip.holati.value == "tahrirlangan"


def test_tasdiqlash_idempotent(client, db, operator, operator_headers, admin_headers, mahsulot_tola, mahsulot_lint):
    eski_partiya = _partiya_yarat(db, mahsulot_tola.id, 510)
    _partiya_yarat(db, mahsulot_lint.id, 511)
    kip = _kip_yarat(db, operator, eski_partiya)
    zayavka_id = client.post(
        "/api/v1/kip-togrilash", json=_payload(kip.id, yangi_partiya_raqami=511), headers=operator_headers
    ).json()["id"]

    j1 = client.post(f"/api/v1/kip-togrilash/{zayavka_id}/tasdiqlash", headers=admin_headers)
    j2 = client.post(f"/api/v1/kip-togrilash/{zayavka_id}/tasdiqlash", headers=admin_headers)
    assert j1.status_code == j2.status_code == 200
    assert j1.json()["holati"] == j2.json()["holati"] == "tasdiqlangan"


def test_tasdiqlash_operatorga_taqiqlangan(client, db, operator, operator_headers, mahsulot_tola, mahsulot_lint):
    eski_partiya = _partiya_yarat(db, mahsulot_tola.id, 512)
    _partiya_yarat(db, mahsulot_lint.id, 513)
    kip = _kip_yarat(db, operator, eski_partiya)
    zayavka_id = client.post(
        "/api/v1/kip-togrilash", json=_payload(kip.id, yangi_partiya_raqami=513), headers=operator_headers
    ).json()["id"]

    assert client.post(f"/api/v1/kip-togrilash/{zayavka_id}/tasdiqlash", headers=operator_headers).status_code == 403


def test_tasdiqlash_notogri_id_404(client, admin_headers):
    assert client.post("/api/v1/kip-togrilash/999999/tasdiqlash", headers=admin_headers).status_code == 404


# --- POST /kip-togrilash/{id}/rad-etish ---


def test_rad_etish_kipni_ozgartirmaydi(client, db, operator, operator_headers, admin_headers, mahsulot_tola, mahsulot_lint):
    eski_partiya = _partiya_yarat(db, mahsulot_tola.id, 514)
    _partiya_yarat(db, mahsulot_lint.id, 515)
    kip = _kip_yarat(db, operator, eski_partiya)
    zayavka_id = client.post(
        "/api/v1/kip-togrilash", json=_payload(kip.id, yangi_partiya_raqami=515), headers=operator_headers
    ).json()["id"]

    javob = client.post(
        f"/api/v1/kip-togrilash/{zayavka_id}/rad-etish",
        json={"izoh": "Kip to'g'ri, o'zgartirish shart emas"},
        headers=admin_headers,
    )
    assert javob.status_code == 200
    assert javob.json()["holati"] == "rad_etilgan"

    db.refresh(kip)
    assert kip.partiya_id == eski_partiya.id
    assert kip.holati.value == "aktiv"


def test_rad_etilganni_keyin_tasdiqlab_bolmaydi(client, db, operator, operator_headers, admin_headers, mahsulot_tola, mahsulot_lint):
    eski_partiya = _partiya_yarat(db, mahsulot_tola.id, 516)
    _partiya_yarat(db, mahsulot_lint.id, 517)
    kip = _kip_yarat(db, operator, eski_partiya)
    zayavka_id = client.post(
        "/api/v1/kip-togrilash", json=_payload(kip.id, yangi_partiya_raqami=517), headers=operator_headers
    ).json()["id"]

    client.post(f"/api/v1/kip-togrilash/{zayavka_id}/rad-etish", headers=admin_headers)
    javob = client.post(f"/api/v1/kip-togrilash/{zayavka_id}/tasdiqlash", headers=admin_headers)
    assert javob.status_code == 200
    assert javob.json()["holati"] == "rad_etilgan"

    db.refresh(kip)
    assert kip.partiya_id == eski_partiya.id

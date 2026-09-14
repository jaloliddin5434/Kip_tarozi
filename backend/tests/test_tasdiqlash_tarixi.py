"""GET /tasdiqlash-tarixi — "Kamera tasdiqlari" va "Kip to'g'irlash so'rovlari"
ekranlarini birlashtirish uchun yangi endpoint. Ikkala manbadan (kamera-tasdiq
so'rovlari, kip-to'g'irlash zayavkalari) kelgan yozuvlarni BITTA
normallashtirilgan ro'yxatga (`tur` maydoni bilan) birlashtiradi.

Testlar to'g'ridan-to'g'ri DB orqali (operator/kamera/Telegram oqimlarini
qayta o'tmasdan) ma'lumot tayyorlaydi — faqat ushbu ro'yxat-endpointning
o'zini (birlashtirish, filtrlash, sahifalash) sinash uchun."""

import uuid
from datetime import date, datetime, timedelta, timezone

import pytest

from app.core.config import settings
from app.models.foydalanuvchi import Smena
from app.models.kamera_tasdiq import KameraTasdiqHolati, KameraTasdiqSorovi
from app.models.kip import Kip, KipHolati
from app.models.kip_togrilash import KipTogrilashHolati, KipTogrilashZayavkasi
from app.models.mahsulot import Mahsulot
from app.models.partiya import Partiya, PartiyaHolati


@pytest.fixture()
def kamera_surat_bermaydi(monkeypatch, tmp_path):
    """Kamera SOZLANGAN, lekin snapshot None qaytaradi (ishlamayapti) — qarang
    test_kamera_tasdiq.py'dagi bir xil fixture."""
    monkeypatch.setattr(settings, "KAMERA_IP", "10.0.0.9")
    monkeypatch.setattr(settings, "KAMERA_LOGIN", "admin")
    monkeypatch.setattr(settings, "KAMERA_PAROL", "sirli")
    monkeypatch.setattr(settings, "STORAGE_PATH", str(tmp_path))
    monkeypatch.setattr("app.services.kamera.snapshot_ol", lambda: None)


@pytest.fixture(autouse=True)
def _telegram_jim(monkeypatch):
    monkeypatch.setattr("app.api.v1.routes.kiplar.xatolik_xabari_tugma_bilan", lambda db, matn, **kw: None)


def _kiplar_payload(partiya_id: int, ogirlik: float) -> dict:
    return {
        "mijoz_id": str(uuid.uuid4()),
        "partiya_id": partiya_id,
        "ogirlik": ogirlik,
        "mahalliy_vaqt": datetime.now(timezone.utc).isoformat(),
    }


def _partiya_yarat(db, mahsulot_id, raqami):
    partiya = Partiya(mahsulot_id=mahsulot_id, partiya_raqami=raqami, holati=PartiyaHolati.ochiq)
    db.add(partiya)
    db.commit()
    db.refresh(partiya)
    return partiya


def _kip_yarat(db, partiya_id, kip_raqami, operator_id, ogirlik=100.0):
    vaqt = datetime.now(timezone.utc)
    kip = Kip(
        mijoz_id=str(uuid.uuid4()),
        partiya_id=partiya_id,
        kip_raqami=kip_raqami,
        ogirlik=ogirlik,
        smena=Smena.A,
        operator_id=operator_id,
        mahalliy_vaqt=vaqt,
        vaqt=vaqt,
        holati=KipHolati.aktiv,
    )
    db.add(kip)
    db.commit()
    db.refresh(kip)
    return kip


def _kamera_sorov_yarat(
    db,
    partiya_id,
    operator_id,
    *,
    ogirlik=105.3,
    holati=KameraTasdiqHolati.kutilmoqda,
    vaqt=None,
    hal_qilgan_id=None,
    hal_qilingan_vaqt=None,
    izoh=None,
):
    vaqt = vaqt or datetime.now(timezone.utc)
    sorov = KameraTasdiqSorovi(
        mijoz_id=str(uuid.uuid4()),
        partiya_id=partiya_id,
        ogirlik=ogirlik,
        smena=Smena.A,
        operator_id=operator_id,
        mahalliy_vaqt=vaqt,
        vaqt=vaqt,
        holati=holati,
        hal_qilgan_id=hal_qilgan_id,
        hal_qilingan_vaqt=hal_qilingan_vaqt,
        izoh=izoh,
    )
    db.add(sorov)
    db.commit()
    db.refresh(sorov)
    return sorov


def _togrilash_zayavka_yarat(
    db,
    kip_id,
    operator_id,
    eski_mahsulot_id,
    eski_partiya_id,
    yangi_mahsulot_id,
    yangi_partiya_id,
    *,
    sabab="Mahsulot xato tanlandi",
    holati=KipTogrilashHolati.kutilmoqda,
    vaqt=None,
    hal_qilgan_id=None,
    hal_qilingan_vaqt=None,
    izoh=None,
):
    vaqt = vaqt or datetime.now(timezone.utc)
    zayavka = KipTogrilashZayavkasi(
        kip_id=kip_id,
        operator_id=operator_id,
        eski_mahsulot_id=eski_mahsulot_id,
        eski_partiya_id=eski_partiya_id,
        yangi_mahsulot_id=yangi_mahsulot_id,
        yangi_partiya_id=yangi_partiya_id,
        sabab=sabab,
        vaqt=vaqt,
        holati=holati,
        hal_qilgan_id=hal_qilgan_id,
        hal_qilingan_vaqt=hal_qilingan_vaqt,
        izoh=izoh,
    )
    db.add(zayavka)
    db.commit()
    db.refresh(zayavka)
    return zayavka


def test_operator_kira_olmaydi(client, operator_headers):
    javob = client.get("/api/v1/tasdiqlash-tarixi", headers=operator_headers)
    assert javob.status_code == 403


def test_royxat_bosh_bolsa_bosh_royxat_qaytaradi(client, admin_headers):
    javob = client.get("/api/v1/tasdiqlash-tarixi", headers=admin_headers).json()
    assert javob["items"] == []
    assert javob["jami"] == 0


def test_royxatda_ikkala_tur_ham_korinadi(client, db, admin, admin_headers, operator, mahsulot_tola):
    lint = Mahsulot(kod="lint", nomi="Lint")
    db.add(lint)
    db.commit()

    partiya = _partiya_yarat(db, mahsulot_tola.id, 501)
    lint_partiya = _partiya_yarat(db, lint.id, 502)
    kip = _kip_yarat(db, partiya.id, 1, operator.id)

    _kamera_sorov_yarat(db, partiya.id, operator.id, ogirlik=105.3)
    _togrilash_zayavka_yarat(db, kip.id, operator.id, mahsulot_tola.id, partiya.id, lint.id, lint_partiya.id)

    javob = client.get("/api/v1/tasdiqlash-tarixi", headers=admin_headers).json()
    assert javob["jami"] == 2
    turlar = {item["tur"] for item in javob["items"]}
    assert turlar == {"kamera", "kip_togrilash"}


def test_kamera_yozuvi_maydonlari_togri(client, db, admin, admin_headers, operator, mahsulot_tola):
    partiya = _partiya_yarat(db, mahsulot_tola.id, 503)
    sorov = _kamera_sorov_yarat(
        db,
        partiya.id,
        operator.id,
        ogirlik=105.3,
        holati=KameraTasdiqHolati.tasdiqlangan,
        hal_qilgan_id=admin.id,
        hal_qilingan_vaqt=datetime.now(timezone.utc),
    )

    javob = client.get("/api/v1/tasdiqlash-tarixi", headers=admin_headers).json()
    yozuv = javob["items"][0]
    assert yozuv["tur"] == "kamera"
    assert yozuv["id"] == sorov.id
    assert yozuv["operator_ism"] == operator.ism
    assert yozuv["tavsif"] == "Tola #503, 105.3 kg"
    assert yozuv["sabab"] is None
    assert yozuv["holati"] == "tasdiqlangan"
    assert yozuv["hal_qilgan_ism"] == admin.ism


def test_kip_togrilash_yozuvi_maydonlari_togri(client, db, admin, admin_headers, operator, mahsulot_tola):
    lint = Mahsulot(kod="lint", nomi="Lint")
    db.add(lint)
    db.commit()
    eski_partiya = _partiya_yarat(db, mahsulot_tola.id, 504)
    yangi_partiya = _partiya_yarat(db, lint.id, 505)
    kip = _kip_yarat(db, eski_partiya.id, 7, operator.id)

    zayavka = _togrilash_zayavka_yarat(
        db,
        kip.id,
        operator.id,
        mahsulot_tola.id,
        eski_partiya.id,
        lint.id,
        yangi_partiya.id,
        sabab="Noto'g'ri mahsulot tanlandi",
        holati=KipTogrilashHolati.rad_etilgan,
        hal_qilgan_id=admin.id,
        hal_qilingan_vaqt=datetime.now(timezone.utc),
        izoh="Kip allaqachon hisobotga kiritilgan",
    )

    javob = client.get("/api/v1/tasdiqlash-tarixi", headers=admin_headers).json()
    yozuv = javob["items"][0]
    assert yozuv["tur"] == "kip_togrilash"
    assert yozuv["id"] == zayavka.id
    assert yozuv["tavsif"] == "Kip №7: Tola #504 -> Lint #505"
    assert yozuv["sabab"] == "Noto'g'ri mahsulot tanlandi"
    assert yozuv["holati"] == "rad_etilgan"
    assert yozuv["hal_qilgan_ism"] == admin.ism
    assert yozuv["izoh"] == "Kip allaqachon hisobotga kiritilgan"


def test_royxat_vaqt_boyicha_kamayish_tartibida(client, db, admin, admin_headers, operator, mahsulot_tola):
    partiya = _partiya_yarat(db, mahsulot_tola.id, 506)
    kip = _kip_yarat(db, partiya.id, 1, operator.id)
    eski = datetime.now(timezone.utc) - timedelta(hours=2)
    yangi = datetime.now(timezone.utc) - timedelta(minutes=1)

    _kamera_sorov_yarat(db, partiya.id, operator.id, vaqt=eski)
    _togrilash_zayavka_yarat(db, kip.id, operator.id, mahsulot_tola.id, partiya.id, mahsulot_tola.id, partiya.id, vaqt=yangi)

    javob = client.get("/api/v1/tasdiqlash-tarixi", headers=admin_headers).json()
    assert [item["tur"] for item in javob["items"]] == ["kip_togrilash", "kamera"]


def test_holati_filtri_ikkala_turga_ham_taalluqli(client, db, admin, admin_headers, operator, mahsulot_tola):
    partiya = _partiya_yarat(db, mahsulot_tola.id, 507)
    kip = _kip_yarat(db, partiya.id, 1, operator.id)

    _kamera_sorov_yarat(db, partiya.id, operator.id, holati=KameraTasdiqHolati.kutilmoqda)
    _kamera_sorov_yarat(
        db, partiya.id, operator.id, holati=KameraTasdiqHolati.tasdiqlangan, hal_qilingan_vaqt=datetime.now(timezone.utc)
    )
    _togrilash_zayavka_yarat(
        db, kip.id, operator.id, mahsulot_tola.id, partiya.id, mahsulot_tola.id, partiya.id,
        holati=KipTogrilashHolati.kutilmoqda,
    )
    _togrilash_zayavka_yarat(
        db, kip.id, operator.id, mahsulot_tola.id, partiya.id, mahsulot_tola.id, partiya.id,
        holati=KipTogrilashHolati.rad_etilgan, hal_qilingan_vaqt=datetime.now(timezone.utc),
    )

    javob = client.get(
        "/api/v1/tasdiqlash-tarixi", params={"holati": "kutilmoqda"}, headers=admin_headers
    ).json()
    assert javob["jami"] == 2
    assert all(item["holati"] == "kutilmoqda" for item in javob["items"])


def test_hal_qilingan_sana_filtri_faqat_shu_kunda_hal_qilinganlarni_qaytaradi(
    client, db, admin, admin_headers, operator, mahsulot_tola
):
    """Kalendarning asosiy talabi: bir kunga bosilganda O'SHA KUNDA hal
    qilingan (tasdiqlangan/rad etilgan) BARCHA yozuvlar (ikkala turi ham)
    ko'rinishi kerak — boshqa kunda hal qilinganlar va hali kutilayotganlar
    chiqib qolmasligi kerak."""
    partiya = _partiya_yarat(db, mahsulot_tola.id, 508)
    kip = _kip_yarat(db, partiya.id, 1, operator.id)

    maqsad_kun = date(2026, 9, 10)
    boshqa_kun = date(2026, 9, 9)
    maqsad_vaqt = datetime(2026, 9, 10, 14, 30, tzinfo=timezone.utc)
    boshqa_vaqt = datetime(2026, 9, 9, 14, 30, tzinfo=timezone.utc)

    kamera_maqsadda = _kamera_sorov_yarat(
        db, partiya.id, operator.id, holati=KameraTasdiqHolati.tasdiqlangan,
        hal_qilgan_id=admin.id, hal_qilingan_vaqt=maqsad_vaqt,
    )
    togrilash_maqsadda = _togrilash_zayavka_yarat(
        db, kip.id, operator.id, mahsulot_tola.id, partiya.id, mahsulot_tola.id, partiya.id,
        holati=KipTogrilashHolati.rad_etilgan, hal_qilgan_id=admin.id, hal_qilingan_vaqt=maqsad_vaqt,
        izoh="Sabab yozildi",
    )
    # Boshqa kunda hal qilingan — chiqmasligi kerak
    _kamera_sorov_yarat(
        db, partiya.id, operator.id, holati=KameraTasdiqHolati.tasdiqlangan,
        hal_qilgan_id=admin.id, hal_qilingan_vaqt=boshqa_vaqt,
    )
    # Hali kutilmoqda (hal_qilingan_vaqt=None) — chiqmasligi kerak
    _kamera_sorov_yarat(db, partiya.id, operator.id, holati=KameraTasdiqHolati.kutilmoqda)
    _togrilash_zayavka_yarat(
        db, kip.id, operator.id, mahsulot_tola.id, partiya.id, mahsulot_tola.id, partiya.id,
        holati=KipTogrilashHolati.kutilmoqda,
    )

    javob = client.get(
        "/api/v1/tasdiqlash-tarixi",
        params={"hal_qilingan_sana": maqsad_kun.isoformat()},
        headers=admin_headers,
    ).json()

    assert javob["jami"] == 2
    ids_by_tur = {item["tur"]: item["id"] for item in javob["items"]}
    assert ids_by_tur == {"kamera": kamera_maqsadda.id, "kip_togrilash": togrilash_maqsadda.id}
    for item in javob["items"]:
        assert item["hal_qilgan_ism"] == admin.ism
    assert boshqa_kun != maqsad_kun  # sog'lomlik tekshiruvi — ikki kun chindan farqli


def test_sahifalash_ishlaydi(client, db, admin, admin_headers, operator, mahsulot_tola):
    partiya = _partiya_yarat(db, mahsulot_tola.id, 509)
    for i in range(5):
        _kamera_sorov_yarat(db, partiya.id, operator.id, vaqt=datetime.now(timezone.utc) - timedelta(minutes=i))

    birinchi_sahifa = client.get(
        "/api/v1/tasdiqlash-tarixi", params={"sahifa": 1, "sahifa_hajmi": 2}, headers=admin_headers
    ).json()
    assert birinchi_sahifa["jami"] == 5
    assert len(birinchi_sahifa["items"]) == 2

    ikkinchi_sahifa = client.get(
        "/api/v1/tasdiqlash-tarixi", params={"sahifa": 2, "sahifa_hajmi": 2}, headers=admin_headers
    ).json()
    assert len(ikkinchi_sahifa["items"]) == 2
    assert birinchi_sahifa["items"][0]["id"] != ikkinchi_sahifa["items"][0]["id"]


def test_kamera_dublikat_shubhasi_yangi_endpointda_ham_korinadi(
    client, operator_headers, admin_headers, mahsulot_tola, kamera_surat_bermaydi
):
    """Eski `/kamera-tasdiq` ro'yxatidagi dublikat-shubhasi ogohlantirishi
    (bitta partiyaga yaqin vaqtda, deyarli bir xil og'irlikdagi ikkita
    so'rov) YANGI birlashtirilgan endpointda ham YO'QOLMASLIGI kerak —
    qarang test_kamera_tasdiq.py::test_royxatda_dublikat_shubhasi_ikkita_yaqin_sorov
    (bir xil stsenariy, shu yerda YANGI endpoint orqali tasdiqlanadi)."""
    partiya = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": 510}, headers=operator_headers
    ).json()

    j1 = client.post("/api/v1/kiplar", json=_kiplar_payload(partiya["id"], 77.0), headers=operator_headers)
    sorov1_id = j1.json()["sorov_id"]
    j2 = client.post("/api/v1/kiplar", json=_kiplar_payload(partiya["id"], 77.2), headers=operator_headers)
    sorov2_id = j2.json()["sorov_id"]

    javob = client.get("/api/v1/tasdiqlash-tarixi", headers=admin_headers).json()
    items_by_id = {i["id"]: i for i in javob["items"] if i["tur"] == "kamera"}

    assert items_by_id[sorov1_id]["dublikat_shubhasi"] is True
    assert items_by_id[sorov2_id]["dublikat_shubhasi"] is True


def test_kip_togrilash_yozuvida_dublikat_shubhasi_doim_false(client, db, admin_headers, operator, mahsulot_tola):
    partiya = _partiya_yarat(db, mahsulot_tola.id, 511)
    kip = _kip_yarat(db, partiya.id, 1, operator.id)
    _togrilash_zayavka_yarat(db, kip.id, operator.id, mahsulot_tola.id, partiya.id, mahsulot_tola.id, partiya.id)

    javob = client.get("/api/v1/tasdiqlash-tarixi", headers=admin_headers).json()
    yozuv = next(i for i in javob["items"] if i["tur"] == "kip_togrilash")
    assert yozuv["dublikat_shubhasi"] is False

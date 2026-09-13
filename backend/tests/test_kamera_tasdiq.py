"""'Kamera ishlamasa — Admin ruxsati' oqimi (1-bosqich: Admin panel orqali).

Hech bir test real kameraga yoki Telegramga chiqmaydi: snapshot_ol / xatolik_xabari
mock qilinadi.
"""

import uuid
from datetime import datetime, timezone

import pytest

from app.core.config import settings
from app.core.security import parolni_hash, token_yarat
from app.models.foydalanuvchi import Foydalanuvchi, Rol, Smena
from app.models.kamera_tasdiq import KameraTasdiqHolati, KameraTasdiqSorovi
from app.models.kip import Kip


@pytest.fixture()
def kamera_surat_bermaydi(monkeypatch, tmp_path):
    """Kamera SOZLANGAN, lekin snapshot None qaytaradi (ishlamayapti)."""
    monkeypatch.setattr(settings, "KAMERA_IP", "10.0.0.9")
    monkeypatch.setattr(settings, "KAMERA_LOGIN", "admin")
    monkeypatch.setattr(settings, "KAMERA_PAROL", "sirli")
    monkeypatch.setattr(settings, "STORAGE_PATH", str(tmp_path))
    monkeypatch.setattr("app.services.kamera.snapshot_ol", lambda: None)


@pytest.fixture(autouse=True)
def _telegram_jim(monkeypatch):
    yuborilgan = []
    monkeypatch.setattr(
        "app.api.v1.routes.kiplar.xatolik_xabari_tugma_bilan",
        lambda db, matn, **kw: yuborilgan.append(matn),
    )
    return yuborilgan


@pytest.fixture()
def operator_b_headers(db) -> dict:
    op_b = Foydalanuvchi(
        ism="Smena B", login="smena_b", parol_hash=parolni_hash("parolB"), rol=Rol.operator, smena=Smena.B
    )
    db.add(op_b)
    db.commit()
    db.refresh(op_b)
    token = token_yarat({"sub": str(op_b.id), "rol": "operator", "smena": "B", "tv": op_b.token_versiyasi})
    return {"Authorization": f"Bearer {token}"}


def _payload(partiya_id: int, ogirlik: float = 141.0) -> dict:
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


# --- POST /kiplar: kamera ishlamasa 202 + bloklovchi so'rov ---


def test_kamera_ishlamasa_kip_saqlanmaydi_202(
    client, db, operator_headers, mahsulot_tola, kamera_surat_bermaydi, _telegram_jim
):
    partiya = _partiya(client, operator_headers, 301)
    javob = client.post("/api/v1/kiplar", json=_payload(partiya["id"]), headers=operator_headers)

    assert javob.status_code == 202
    tana = javob.json()
    assert tana["kamera_tasdiq_kutilmoqda"] is True
    sorov_id = tana["sorov_id"]

    # Kip YO'Q, so'rov bor va "kutilmoqda"
    assert db.query(Kip).filter(Kip.partiya_id == partiya["id"]).count() == 0
    sorov = db.get(KameraTasdiqSorovi, sorov_id)
    assert sorov is not None
    assert sorov.holati == KameraTasdiqHolati.kutilmoqda
    assert sorov.operator_id is not None

    # Telegramga ogohlantirish yuborildi
    assert any("KAMERA ISHLAMADI" in m for m in _telegram_jim)


def test_202_idempotent_bir_xil_mijoz_id(
    client, db, operator_headers, mahsulot_tola, kamera_surat_bermaydi
):
    partiya = _partiya(client, operator_headers, 302)
    tana = _payload(partiya["id"])

    j1 = client.post("/api/v1/kiplar", json=tana, headers=operator_headers)
    j2 = client.post("/api/v1/kiplar", json=tana, headers=operator_headers)

    assert j1.status_code == j2.status_code == 202
    assert j1.json()["sorov_id"] == j2.json()["sorov_id"]
    assert db.query(KameraTasdiqSorovi).filter_by(mijoz_id=tana["mijoz_id"]).count() == 1


# --- GET /kamera-tasdiq/{id}/holat ---


def test_holat_operator_ozini_koradi_boshqasi_403(
    client, operator_headers, operator_b_headers, mahsulot_tola, kamera_surat_bermaydi
):
    partiya = _partiya(client, operator_headers, 303)
    sorov_id = client.post("/api/v1/kiplar", json=_payload(partiya["id"]), headers=operator_headers).json()["sorov_id"]

    o_javob = client.get(f"/api/v1/kamera-tasdiq/{sorov_id}/holat", headers=operator_headers)
    assert o_javob.status_code == 200
    assert o_javob.json()["holati"] == "kutilmoqda"

    b_javob = client.get(f"/api/v1/kamera-tasdiq/{sorov_id}/holat", headers=operator_b_headers)
    assert b_javob.status_code == 403

    assert client.get(f"/api/v1/kamera-tasdiq/{sorov_id}/holat").status_code == 401


def test_holat_notogri_id_404(client, operator_headers):
    assert client.get("/api/v1/kamera-tasdiq/999999/holat", headers=operator_headers).status_code == 404


def test_mening_kutilayotganim(
    client, operator_headers, operator_b_headers, admin_headers, mahsulot_tola, kamera_surat_bermaydi
):
    # Hech narsa yo'q -> null
    assert client.get("/api/v1/kamera-tasdiq/mening-kutilayotganim", headers=operator_headers).json() is None

    partiya = _partiya(client, operator_headers, 311)
    sorov_id = client.post("/api/v1/kiplar", json=_payload(partiya["id"]), headers=operator_headers).json()["sorov_id"]

    # A operatori — o'z so'rovini ko'radi
    meniki = client.get("/api/v1/kamera-tasdiq/mening-kutilayotganim", headers=operator_headers).json()
    assert meniki["id"] == sorov_id and meniki["holati"] == "kutilmoqda"
    # `vaqt` — bloklovchi dialogdagi "necha vaqtdan beri kutilmoqda"
    # hisoblagichi uchun (operator ilovani qayta ochsa ham to'g'ri davom etsin)
    assert meniki["vaqt"] is not None

    holat_javobi = client.get(f"/api/v1/kamera-tasdiq/{sorov_id}/holat", headers=operator_headers).json()
    assert holat_javobi["vaqt"] == meniki["vaqt"]

    # B operatori — bo'sh (boshqa operatorning so'rovi ko'rinmaydi)
    assert client.get("/api/v1/kamera-tasdiq/mening-kutilayotganim", headers=operator_b_headers).json() is None

    # admin — operator emas -> 403
    assert client.get("/api/v1/kamera-tasdiq/mening-kutilayotganim", headers=admin_headers).status_code == 403

    # Tasdiqlangandan keyin -> yana null
    client.post(f"/api/v1/kamera-tasdiq/{sorov_id}/tasdiqlash", headers=admin_headers)
    assert client.get("/api/v1/kamera-tasdiq/mening-kutilayotganim", headers=operator_headers).json() is None


# --- GET /kamera-tasdiq (admin ro'yxat) ---


def test_royxat_admin_koradi_operator_403(
    client, operator_headers, admin_headers, mahsulot_tola, kamera_surat_bermaydi
):
    partiya = _partiya(client, operator_headers, 304)
    client.post("/api/v1/kiplar", json=_payload(partiya["id"]), headers=operator_headers)

    assert client.get("/api/v1/kamera-tasdiq", headers=operator_headers).status_code == 403

    javob = client.get("/api/v1/kamera-tasdiq", params={"holati": "kutilmoqda"}, headers=admin_headers)
    assert javob.status_code == 200
    data = javob.json()
    assert data["jami"] >= 1
    yozuv = data["items"][0]
    assert yozuv["mahsulot_nomi"] == "Tola"
    assert yozuv["partiya_raqami"] == 304
    assert yozuv["operator_ism"]
    assert yozuv["holati"] == "kutilmoqda"


# --- POST /kamera-tasdiq/{id}/tasdiqlash ---


def test_tasdiqlash_kipni_suratsiz_yaratadi(
    client, db, operator_headers, admin_headers, mahsulot_tola, kamera_surat_bermaydi
):
    partiya = _partiya(client, operator_headers, 305)
    tana = _payload(partiya["id"], ogirlik=137.5)
    sorov_id = client.post("/api/v1/kiplar", json=tana, headers=operator_headers).json()["sorov_id"]

    javob = client.post(f"/api/v1/kamera-tasdiq/{sorov_id}/tasdiqlash", headers=admin_headers)
    assert javob.status_code == 200
    assert javob.json()["holati"] == "tasdiqlangan"
    kip_id = javob.json()["kip_id"]
    assert kip_id is not None

    kip = db.get(Kip, kip_id)
    assert kip.surat_yoli is None
    assert kip.mijoz_id == tana["mijoz_id"]
    assert float(kip.ogirlik) == 137.5
    assert kip.smena == Smena.A

    # Operator polling endi tasdiqlangan + kip_id ko'radi
    holat = client.get(f"/api/v1/kamera-tasdiq/{sorov_id}/holat", headers=operator_headers).json()
    assert holat["holati"] == "tasdiqlangan"
    assert holat["kip_id"] == kip_id


def test_tasdiqlash_idempotent(
    client, db, operator_headers, admin_headers, mahsulot_tola, kamera_surat_bermaydi
):
    partiya = _partiya(client, operator_headers, 306)
    sorov_id = client.post("/api/v1/kiplar", json=_payload(partiya["id"]), headers=operator_headers).json()["sorov_id"]

    j1 = client.post(f"/api/v1/kamera-tasdiq/{sorov_id}/tasdiqlash", headers=admin_headers)
    j2 = client.post(f"/api/v1/kamera-tasdiq/{sorov_id}/tasdiqlash", headers=admin_headers)
    assert j1.status_code == j2.status_code == 200
    assert j1.json()["kip_id"] == j2.json()["kip_id"]
    assert db.query(Kip).filter_by(partiya_id=partiya["id"]).count() == 1


def test_tasdiqlash_operatorga_taqiqlangan(
    client, operator_headers, mahsulot_tola, kamera_surat_bermaydi
):
    partiya = _partiya(client, operator_headers, 307)
    sorov_id = client.post("/api/v1/kiplar", json=_payload(partiya["id"]), headers=operator_headers).json()["sorov_id"]
    assert client.post(f"/api/v1/kamera-tasdiq/{sorov_id}/tasdiqlash", headers=operator_headers).status_code == 403


def test_tasdiqlash_notogri_id_404(client, admin_headers):
    assert client.post("/api/v1/kamera-tasdiq/999999/tasdiqlash", headers=admin_headers).status_code == 404


# --- POST /kamera-tasdiq/{id}/rad-etish ---


def test_rad_etish_kip_yaratmaydi(
    client, db, operator_headers, admin_headers, mahsulot_tola, kamera_surat_bermaydi
):
    partiya = _partiya(client, operator_headers, 308)
    sorov_id = client.post("/api/v1/kiplar", json=_payload(partiya["id"]), headers=operator_headers).json()["sorov_id"]

    javob = client.post(
        f"/api/v1/kamera-tasdiq/{sorov_id}/rad-etish",
        json={"izoh": "Kamera tuzaldi, qaytadan torting"},
        headers=admin_headers,
    )
    assert javob.status_code == 200
    assert javob.json()["holati"] == "rad_etilgan"
    assert javob.json()["kip_id"] is None
    assert db.query(Kip).filter_by(partiya_id=partiya["id"]).count() == 0

    holat = client.get(f"/api/v1/kamera-tasdiq/{sorov_id}/holat", headers=operator_headers).json()
    assert holat["holati"] == "rad_etilgan"
    assert holat["izoh"] == "Kamera tuzaldi, qaytadan torting"


def test_rad_etilgan_sorovni_tasdiqlab_bolmaydi(
    client, db, operator_headers, admin_headers, mahsulot_tola, kamera_surat_bermaydi
):
    partiya = _partiya(client, operator_headers, 309)
    sorov_id = client.post("/api/v1/kiplar", json=_payload(partiya["id"]), headers=operator_headers).json()["sorov_id"]

    client.post(f"/api/v1/kamera-tasdiq/{sorov_id}/rad-etish", headers=admin_headers)
    # rad etilgandan keyin tasdiqlash — holat o'zgarmaydi, kip yaratilmaydi (idempotent)
    javob = client.post(f"/api/v1/kamera-tasdiq/{sorov_id}/tasdiqlash", headers=admin_headers)
    assert javob.status_code == 200
    assert javob.json()["holati"] == "rad_etilgan"
    assert db.query(Kip).filter_by(partiya_id=partiya["id"]).count() == 0


# --- AUDIT TUZATISHI: ro'yxatdagi "dublikat shubhasi" ogohlantirishi ---
# (oddiy oqimdagi dedup-tekshiruvi kamera ISHLAMAGAN payt chaqirilmasligi —
# real sinovda tasdiqlangan audit topilmasi)


def test_royxatda_dublikat_shubhasi_ikkita_yaqin_sorov(
    client, db, operator_headers, admin_headers, mahsulot_tola, kamera_surat_bermaydi
):
    """Bitta partiyaga bir necha soniya farq bilan deyarli bir xil og'irlikda
    ikkita so'rov kelsa — ikkalasi ham ro'yxatda `dublikat_shubhasi=True`
    bilan ko'rinishi kerak (ADMIN hali qaror qabul qilmagan, kutilmoqda)."""
    partiya = _partiya(client, operator_headers, 320)

    j1 = client.post("/api/v1/kiplar", json=_payload(partiya["id"], ogirlik=77.0), headers=operator_headers)
    sorov1_id = j1.json()["sorov_id"]
    j2 = client.post("/api/v1/kiplar", json=_payload(partiya["id"], ogirlik=77.2), headers=operator_headers)
    sorov2_id = j2.json()["sorov_id"]

    javob = client.get("/api/v1/kamera-tasdiq", params={"holati": "kutilmoqda"}, headers=admin_headers)
    assert javob.status_code == 200
    items_by_id = {i["id"]: i for i in javob.json()["items"]}

    assert items_by_id[sorov1_id]["dublikat_shubhasi"] is True
    assert items_by_id[sorov2_id]["dublikat_shubhasi"] is True

    # Admin ikkalasini ham baribir TASDIQLASHI mumkin (avtomatik bloklanmaydi) —
    # ogohlantirish faqat ko'rinadigan, majburiy emas.
    t1 = client.post(f"/api/v1/kamera-tasdiq/{sorov1_id}/tasdiqlash", headers=admin_headers)
    t2 = client.post(f"/api/v1/kamera-tasdiq/{sorov2_id}/tasdiqlash", headers=admin_headers)
    assert t1.status_code == t2.status_code == 200
    assert t1.json()["kip_id"] != t2.json()["kip_id"]


def test_royxatda_dublikat_shubhasi_yolgiz_sorov_uchun_yoq(
    client, admin_headers, operator_headers, mahsulot_tola, kamera_surat_bermaydi
):
    """Boshqa yaqin yozuv bo'lmasa — ogohlantirish chiqmasligi kerak."""
    partiya = _partiya(client, operator_headers, 321)
    sorov_id = client.post(
        "/api/v1/kiplar", json=_payload(partiya["id"], ogirlik=90.0), headers=operator_headers
    ).json()["sorov_id"]

    javob = client.get("/api/v1/kamera-tasdiq", params={"holati": "kutilmoqda"}, headers=admin_headers)
    yozuv = next(i for i in javob.json()["items"] if i["id"] == sorov_id)
    assert yozuv["dublikat_shubhasi"] is False


def test_royxatda_dublikat_shubhasi_uzoq_ogirlik_farqida_yoq(
    client, admin_headers, operator_headers, mahsulot_tola, kamera_surat_bermaydi
):
    """Bir xil partiya, yaqin vaqt, LEKIN og'irlik farqi tolerantlikdan katta
    bo'lsa — ogohlantirish chiqmasligi kerak (haqiqiy ikkita alohida kip)."""
    partiya = _partiya(client, operator_headers, 322)
    client.post("/api/v1/kiplar", json=_payload(partiya["id"], ogirlik=100.0), headers=operator_headers)
    sorov2_id = client.post(
        "/api/v1/kiplar", json=_payload(partiya["id"], ogirlik=150.0), headers=operator_headers
    ).json()["sorov_id"]

    javob = client.get("/api/v1/kamera-tasdiq", params={"holati": "kutilmoqda"}, headers=admin_headers)
    yozuv = next(i for i in javob.json()["items"] if i["id"] == sorov2_id)
    assert yozuv["dublikat_shubhasi"] is False


def test_royxatda_dublikat_shubhasi_rad_etilgan_sorov_bilan_solishtirilmaydi(
    client, admin_headers, operator_headers, mahsulot_tola, kamera_surat_bermaydi
):
    """Avval RAD ETILGAN so'rov (masalan operatorning xato urinishi) yangi,
    yaqin og'irlikdagi so'rovni "shubhali" deb belgilamasligi kerak — rad
    etilgan allaqachon hal qilingan, endi ahamiyatsiz."""
    partiya = _partiya(client, operator_headers, 323)
    eski_sorov_id = client.post(
        "/api/v1/kiplar", json=_payload(partiya["id"], ogirlik=60.0), headers=operator_headers
    ).json()["sorov_id"]
    client.post(f"/api/v1/kamera-tasdiq/{eski_sorov_id}/rad-etish", headers=admin_headers)

    yangi_sorov_id = client.post(
        "/api/v1/kiplar", json=_payload(partiya["id"], ogirlik=60.1), headers=operator_headers
    ).json()["sorov_id"]

    javob = client.get("/api/v1/kamera-tasdiq", params={"holati": "kutilmoqda"}, headers=admin_headers)
    yozuv = next(i for i in javob.json()["items"] if i["id"] == yangi_sorov_id)
    assert yozuv["dublikat_shubhasi"] is False


def test_royxatda_dublikat_shubhasi_mavjud_kip_bilan_ham_ishlaydi(
    client, admin_headers, operator_headers, mahsulot_tola, kamera_surat_bermaydi, monkeypatch
):
    """Partiyada ALLAQACHON (oddiy oqimda, kamera ishlaganda) saqlangan kip
    bo'lsa, va endi kamera ishlamay qolib yaqin og'irlikdagi so'rov kelsa —
    bu ham (sorov-sorov emas, sorov-Kip solishtiruvi orqali) shubhali deb
    belgilanishi kerak."""
    partiya = _partiya(client, operator_headers, 324)

    # Kamera hali ISHLAYOTGAN payt (`kamera_surat_bermaydi` fixture sozlagan
    # qiymatlarni shu bitta so'rov uchun vaqtincha bekor qilamiz) oddiy
    # oqimda bitta kip saqlanadi.
    monkeypatch.setattr(settings, "KAMERA_IP", None)
    birinchi = client.post("/api/v1/kiplar", json=_payload(partiya["id"], ogirlik=70.0), headers=operator_headers)
    assert birinchi.status_code == 201
    monkeypatch.setattr(settings, "KAMERA_IP", "10.0.0.9")  # fixture qiymatiga qaytaramiz

    # Endi kamera yana "ishlamay qoladi". Yaqin og'irlikdagi ikkinchi urinish
    # ODDIY oqimdagi dedup-tekshiruvining o'ziga (409) uchrab qolmasligi uchun
    # `majburiy=True` bilan yuboriladi (operator "ha, bu haqiqatan yangi
    # kip" deb tasdiqlagan holatni simulyatsiya qiladi) — shunda so'rov
    # kamera bosqichigacha yetib boradi va "kutilmoqda" so'rov yaratadi.
    ikkinchi_tana = _payload(partiya["id"], ogirlik=70.3)
    ikkinchi_tana["majburiy"] = True
    ikkinchi_sorov_id = client.post("/api/v1/kiplar", json=ikkinchi_tana, headers=operator_headers).json()["sorov_id"]

    javob = client.get("/api/v1/kamera-tasdiq", params={"holati": "kutilmoqda"}, headers=admin_headers)
    yozuv = next(i for i in javob.json()["items"] if i["id"] == ikkinchi_sorov_id)
    assert yozuv["dublikat_shubhasi"] is True


# --- Kamera ISHLAGANDA — oqim o'zgarmaydi ---


def test_kamera_ishlasa_kip_odatdagidek_saqlanadi(
    client, operator_headers, mahsulot_tola, monkeypatch, tmp_path
):
    monkeypatch.setattr(settings, "KAMERA_IP", "10.0.0.9")
    monkeypatch.setattr(settings, "KAMERA_LOGIN", "a")
    monkeypatch.setattr(settings, "KAMERA_PAROL", "b")
    monkeypatch.setattr(settings, "STORAGE_PATH", str(tmp_path))
    monkeypatch.setattr(
        "app.services.kamera.snapshot_ol", lambda: b"\xff\xd8\xff\xe0\x00\x10JFIF" + b"\x00" * 20 + b"\xff\xd9"
    )
    partiya = _partiya(client, operator_headers, 310)
    javob = client.post("/api/v1/kiplar", json=_payload(partiya["id"]), headers=operator_headers)
    assert javob.status_code == 201
    assert javob.json()["surat_yoli"] is not None

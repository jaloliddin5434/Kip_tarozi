import uuid
from datetime import datetime, timezone

from app.core.security import parolni_hash
from app.models.foydalanuvchi import Foydalanuvchi, Rol, Smena
from app.models.mahsulot import Mahsulot


def _kip_yaratish_payload(partiya_id: int, ogirlik: float = 135.5) -> dict:
    return {
        "mijoz_id": str(uuid.uuid4()),
        "partiya_id": partiya_id,
        "ogirlik": ogirlik,
        "mahalliy_vaqt": datetime.now(timezone.utc).isoformat(),
    }


def test_batafsil_mavjud_kipni_qaytaradi(client, operator_headers, admin_headers, mahsulot_tola):
    partiya = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": 200}, headers=operator_headers
    ).json()
    kip = client.post(
        "/api/v1/kiplar", json=_kip_yaratish_payload(partiya["id"], 140.0), headers=operator_headers
    ).json()

    javob = client.get(f"/api/v1/kiplar/{kip['id']}", headers=admin_headers)
    assert javob.status_code == 200
    tana = javob.json()
    assert tana["id"] == kip["id"]
    assert tana["mahsulot_kodi"] == "tola"
    assert tana["mahsulot_nomi"] == "Tola"
    assert tana["partiya_raqami"] == 200
    assert tana["ogirlik"] == 140.0
    assert tana["smena"] == "A"
    assert tana["operator_ism"] == "Smena A"
    assert tana["holati"] == "aktiv"
    assert tana["audit_log"] == []


def test_batafsil_mavjud_bolmagan_id_404(client, admin_headers):
    javob = client.get("/api/v1/kiplar/999999", headers=admin_headers)
    assert javob.status_code == 404


def test_batafsil_operator_boshqa_smenani_korolmaydi(client, db, operator_headers, operator, mahsulot_tola):
    partiya = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": 201}, headers=operator_headers
    ).json()
    kip = client.post("/api/v1/kiplar", json=_kip_yaratish_payload(partiya["id"]), headers=operator_headers).json()

    # o'z smenasi (A) — kira oladi
    ozini = client.get(f"/api/v1/kiplar/{kip['id']}", headers=operator_headers)
    assert ozini.status_code == 200

    # boshqa smenadagi (B) operator — kira olmaydi
    boshqa_operator = Foydalanuvchi(
        ism="Smena B", login="smena_b_batafsil", parol_hash=parolni_hash("parolB"), rol=Rol.operator, smena=Smena.B
    )
    db.add(boshqa_operator)
    db.commit()
    db.refresh(boshqa_operator)

    from app.core.security import token_yarat

    boshqa_token = token_yarat(
        {"sub": str(boshqa_operator.id), "rol": "operator", "smena": "B", "tv": boshqa_operator.token_versiyasi}
    )
    boshqa_headers = {"Authorization": f"Bearer {boshqa_token}"}

    rad_etildi = client.get(f"/api/v1/kiplar/{kip['id']}", headers=boshqa_headers)
    assert rad_etildi.status_code == 403


def test_batafsil_tahrirlangan_kip_audit_log_qaytaradi(client, operator_headers, admin_headers, mahsulot_tola):
    partiya = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": 202}, headers=operator_headers
    ).json()
    kip = client.post(
        "/api/v1/kiplar", json=_kip_yaratish_payload(partiya["id"], 120.0), headers=operator_headers
    ).json()

    tahrirlash = client.patch(
        f"/api/v1/kiplar/{kip['id']}",
        json={"ogirlik": 125.0, "sabab": "Tarozi xatosi tuzatildi"},
        headers=admin_headers,
    )
    assert tahrirlash.status_code == 200

    javob = client.get(f"/api/v1/kiplar/{kip['id']}", headers=admin_headers)
    assert javob.status_code == 200
    tana = javob.json()
    assert tana["ogirlik"] == 125.0
    assert tana["holati"] == "tahrirlangan"
    assert len(tana["audit_log"]) == 1

    yozuv = tana["audit_log"][0]
    assert yozuv["amal"] == "tahrirlandi"
    assert yozuv["sabab"] == "Tarozi xatosi tuzatildi"
    assert yozuv["eski_qiymat"]["ogirlik"] == 120.0
    assert yozuv["yangi_qiymat"]["ogirlik"] == 125.0
    assert yozuv["foydalanuvchi_ism"] == "Test Admin"


def test_tahrirlash_mahsulot_partiya_ozgartirish_ishlaydi(db, client, operator_headers, admin_headers, mahsulot_tola):
    lint = Mahsulot(kod="lint", nomi="Lint")
    db.add(lint)
    db.commit()

    eski_partiya = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": 300}, headers=operator_headers
    ).json()
    yangi_partiya = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "lint", "partiya_raqami": 301}, headers=operator_headers
    ).json()
    kip = client.post(
        "/api/v1/kiplar", json=_kip_yaratish_payload(eski_partiya["id"], 130.0), headers=operator_headers
    ).json()

    tahrirlash = client.patch(
        f"/api/v1/kiplar/{kip['id']}",
        json={"mahsulot_kodi": "lint", "partiya_raqami": 301, "sabab": "Operator xato partiya tanlagan edi"},
        headers=admin_headers,
    )
    assert tahrirlash.status_code == 200
    assert tahrirlash.json()["partiya_id"] == yangi_partiya["id"]

    javob = client.get(f"/api/v1/kiplar/{kip['id']}", headers=admin_headers).json()
    assert javob["mahsulot_kodi"] == "lint"
    assert javob["mahsulot_nomi"] == "Lint"
    assert javob["partiya_raqami"] == 301
    assert javob["holati"] == "tahrirlangan"

    yozuv = javob["audit_log"][0]
    assert yozuv["sabab"] == "Operator xato partiya tanlagan edi"
    assert yozuv["eski_qiymat"]["mahsulot_kodi"] == "tola"
    assert yozuv["eski_qiymat"]["partiya_raqami"] == 300
    assert yozuv["yangi_qiymat"]["mahsulot_kodi"] == "lint"
    assert yozuv["yangi_qiymat"]["partiya_raqami"] == 301


def test_tahrirlash_yangi_partiyada_kip_raqami_bandligini_hal_qiladi(
    db, client, operator_headers, admin_headers, mahsulot_tola
):
    """Regressiya: yangi partiyada ko'chirilayotgan kipning kip_raqami
    allaqachon band bo'lsa (masalan ikkalasida ham partiyadagi 1-kip bo'lsa),
    tahrirlash uq_kip_partiya_raqam cheklovini buzib 500 bermasligi kerak."""
    lint = Mahsulot(kod="lint_kr", nomi="Lint")
    db.add(lint)
    db.commit()

    eski_partiya = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": 305}, headers=operator_headers
    ).json()
    yangi_partiya = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "lint_kr", "partiya_raqami": 306}, headers=operator_headers
    ).json()

    # Yangi partiyada ALLAQACHON 1-kip bor.
    client.post("/api/v1/kiplar", json=_kip_yaratish_payload(yangi_partiya["id"], 50.0), headers=operator_headers)
    # Ko'chirilayotgan kip ham o'z (eski) partiyasida 1-kip.
    kip = client.post(
        "/api/v1/kiplar", json=_kip_yaratish_payload(eski_partiya["id"], 130.0), headers=operator_headers
    ).json()
    assert kip["kip_raqami"] == 1

    tahrirlash = client.patch(
        f"/api/v1/kiplar/{kip['id']}",
        json={"mahsulot_kodi": "lint_kr", "partiya_raqami": 306, "sabab": "Operator xato partiya tanlagan edi"},
        headers=admin_headers,
    )
    assert tahrirlash.status_code == 200, tahrirlash.text
    assert tahrirlash.json()["partiya_id"] == yangi_partiya["id"]
    assert tahrirlash.json()["kip_raqami"] == 2  # band bo'lgan 1-dan keyingi bo'sh raqam


def test_tahrirlash_notogri_mahsulot_kodi_400(client, operator_headers, admin_headers, mahsulot_tola):
    partiya = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": 302}, headers=operator_headers
    ).json()
    kip = client.post("/api/v1/kiplar", json=_kip_yaratish_payload(partiya["id"]), headers=operator_headers).json()

    javob = client.patch(
        f"/api/v1/kiplar/{kip['id']}",
        json={"mahsulot_kodi": "mavjud_emas", "partiya_raqami": 1, "sabab": "sinov"},
        headers=admin_headers,
    )
    assert javob.status_code == 400


def test_tahrirlash_notogri_partiya_raqami_400(client, operator_headers, admin_headers, mahsulot_tola):
    partiya = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": 303}, headers=operator_headers
    ).json()
    kip = client.post("/api/v1/kiplar", json=_kip_yaratish_payload(partiya["id"]), headers=operator_headers).json()

    javob = client.patch(
        f"/api/v1/kiplar/{kip['id']}",
        json={"mahsulot_kodi": "tola", "partiya_raqami": 999999, "sabab": "sinov"},
        headers=admin_headers,
    )
    assert javob.status_code == 400


def test_tahrirlash_faqat_mahsulot_kodi_400(client, operator_headers, admin_headers, mahsulot_tola):
    partiya = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": 304}, headers=operator_headers
    ).json()
    kip = client.post("/api/v1/kiplar", json=_kip_yaratish_payload(partiya["id"]), headers=operator_headers).json()

    javob = client.patch(
        f"/api/v1/kiplar/{kip['id']}",
        json={"mahsulot_kodi": "tola", "sabab": "sinov"},
        headers=admin_headers,
    )
    assert javob.status_code == 400

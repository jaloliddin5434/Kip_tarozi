import uuid
from datetime import datetime, timezone

from app.core.security import parolni_hash
from app.models.foydalanuvchi import Foydalanuvchi, Rol, Smena


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

    boshqa_token = token_yarat({"sub": str(boshqa_operator.id), "rol": "operator", "smena": "B"})
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

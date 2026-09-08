import uuid
from datetime import datetime, timedelta, timezone

from app.core.config import settings
from app.models.kip import Kip


def _kip_yaratish_payload(partiya_id: int, ogirlik: float = 135.5) -> dict:
    return {
        "mijoz_id": str(uuid.uuid4()),
        "partiya_id": partiya_id,
        "ogirlik": ogirlik,
        "mahalliy_vaqt": datetime.now(timezone.utc).isoformat(),
    }


def test_partiya_ochish_va_qayta_tanlash(client, operator_headers, mahsulot_tola):
    javob = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": 1}, headers=operator_headers
    )
    assert javob.status_code == 200
    partiya_1 = javob.json()
    assert partiya_1["holati"] == "ochiq"
    assert partiya_1["kip_soni"] == 0

    # Xuddi shu raqam bilan qayta so'ralsa — mavjud (ochiq) partiya qaytariladi, yangisi yaratilmaydi
    javob2 = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": 1}, headers=operator_headers
    )
    assert javob2.status_code == 200
    assert javob2.json()["id"] == partiya_1["id"]


def test_yopiq_partiyaga_kip_qosha_olmaydi(client, operator_headers, admin_headers, mahsulot_tola):
    partiya = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": 2}, headers=operator_headers
    ).json()

    yopish = client.patch(f"/api/v1/partiyalar/{partiya['id']}/yopish", headers=operator_headers)
    assert yopish.status_code == 200
    assert yopish.json()["holati"] == "yopiq"

    javob = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": 2}, headers=operator_headers
    )
    assert javob.status_code == 400


def test_kip_raqami_avtomatik_ortadi(client, operator_headers, mahsulot_tola):
    partiya = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": 3}, headers=operator_headers
    ).json()

    kip1 = client.post("/api/v1/kiplar", json=_kip_yaratish_payload(partiya["id"], 130.0), headers=operator_headers)
    assert kip1.status_code == 201
    assert kip1.json()["kip_raqami"] == 1

    kip2 = client.post("/api/v1/kiplar", json=_kip_yaratish_payload(partiya["id"], 128.0), headers=operator_headers)
    assert kip2.status_code == 201
    assert kip2.json()["kip_raqami"] == 2


def test_dublikat_ogohlantirish(client, operator_headers, mahsulot_tola):
    partiya = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": 4}, headers=operator_headers
    ).json()

    birinchi = _kip_yaratish_payload(partiya["id"], 135.0)
    javob1 = client.post("/api/v1/kiplar", json=birinchi, headers=operator_headers)
    assert javob1.status_code == 201

    ikkinchi = _kip_yaratish_payload(partiya["id"], 135.2)  # bir necha soniya ichida, yaqin og'irlik
    javob2 = client.post("/api/v1/kiplar", json=ikkinchi, headers=operator_headers)
    assert javob2.status_code == 409

    # majburiy=true bilan baribir saqlanadi
    ikkinchi["majburiy"] = True
    javob3 = client.post("/api/v1/kiplar", json=ikkinchi, headers=operator_headers)
    assert javob3.status_code == 201


def test_stansiya_id_saqlanadi(client, operator_headers, mahsulot_tola, stansiya):
    partiya = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": 41}, headers=operator_headers
    ).json()

    payload = _kip_yaratish_payload(partiya["id"])
    payload["stansiya_id"] = stansiya.id
    javob = client.post("/api/v1/kiplar", json=payload, headers=operator_headers)

    assert javob.status_code == 201
    assert javob.json()["stansiya_id"] == stansiya.id


def test_mijoz_id_dedup(client, operator_headers, mahsulot_tola):
    partiya = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": 5}, headers=operator_headers
    ).json()

    payload = _kip_yaratish_payload(partiya["id"])
    javob1 = client.post("/api/v1/kiplar", json=payload, headers=operator_headers)
    javob2 = client.post("/api/v1/kiplar", json=payload, headers=operator_headers)  # aynan o'sha mijoz_id

    assert javob1.status_code == 201
    assert javob2.json()["id"] == javob1.json()["id"]  # yangi yozuv yaratilmadi


def test_sinxron_offline_navbatni_saqlaydi_va_deduplaydi(client, operator_headers, mahsulot_tola):
    """Operator ekranidagi offline (lokal) navbat shu endpoint orqali yuboriladi.
    mijoz_id dedup ishlaydi, dublikat-og'irlik ogohlantirishi TEKSHIRILMAYDI."""
    partiya = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": 71}, headers=operator_headers
    ).json()

    a = _kip_yaratish_payload(partiya["id"], 140.0)
    b = _kip_yaratish_payload(partiya["id"], 140.1)  # yaqin og'irlik — jonli saqlashda 409 berardi

    javob = client.post("/api/v1/kiplar/sinxron", json=[a, b], headers=operator_headers)
    assert javob.status_code == 200
    natijalar = javob.json()
    assert [n["holat"] for n in natijalar] == ["saqlandi", "saqlandi"]

    # Qayta yuborilsa — yangi yozuv yaratilmaydi
    qayta = client.post("/api/v1/kiplar/sinxron", json=[a, b], headers=operator_headers)
    assert [n["holat"] for n in qayta.json()] == ["allaqachon_mavjud", "allaqachon_mavjud"]
    assert qayta.json()[0]["kip_id"] == natijalar[0]["kip_id"]


def test_sinxron_yopiq_partiyaga_xato_qaytaradi(client, operator_headers, mahsulot_tola):
    partiya = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": 72}, headers=operator_headers
    ).json()
    client.patch(f"/api/v1/partiyalar/{partiya['id']}/yopish", headers=operator_headers)

    javob = client.post(
        "/api/v1/kiplar/sinxron", json=[_kip_yaratish_payload(partiya["id"])], headers=operator_headers
    )
    assert javob.status_code == 200
    assert javob.json()[0]["holat"] == "xato"


def test_tezkor_bekor_qilish_muddati(client, db, operator_headers, mahsulot_tola):
    partiya = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": 6}, headers=operator_headers
    ).json()
    kip = client.post("/api/v1/kiplar", json=_kip_yaratish_payload(partiya["id"]), headers=operator_headers).json()

    # Hali vaqt o'tmagan — bekor qilish ishlaydi
    bekor = client.post(f"/api/v1/kiplar/{kip['id']}/bekor-qilish", headers=operator_headers)
    assert bekor.status_code == 200
    assert bekor.json()["holati"] == "bekor_qilingan"

    # Muddat o'tgan holatni simulyatsiya qilamiz
    kip2 = client.post("/api/v1/kiplar", json=_kip_yaratish_payload(partiya["id"]), headers=operator_headers).json()
    db_kip = db.get(Kip, kip2["id"])
    db_kip.vaqt = datetime.now(timezone.utc) - timedelta(seconds=settings.BEKOR_QILISH_MUDDATI_SONIYA + 5)
    db.commit()

    kech_bekor = client.post(f"/api/v1/kiplar/{kip2['id']}/bekor-qilish", headers=operator_headers)
    assert kech_bekor.status_code == 403


def test_smena_kunlik_jamlanma(client, operator_headers, mahsulot_tola):
    partiya = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": 42}, headers=operator_headers
    ).json()
    client.post("/api/v1/kiplar", json=_kip_yaratish_payload(partiya["id"], 100.0), headers=operator_headers)
    client.post("/api/v1/kiplar", json=_kip_yaratish_payload(partiya["id"], 50.0), headers=operator_headers)

    bugun = datetime.now(timezone.utc).date().isoformat()
    javob = client.get(f"/api/v1/kiplar/smena/kunlik-jamlanma?sana={bugun}", headers=operator_headers)
    assert javob.status_code == 200
    data = javob.json()
    tola = next(m for m in data["mahsulotlar"] if m["mahsulot_kodi"] == "tola")
    assert tola["soni"] == 2
    assert tola["jami_kg"] == 150.0

    # Boshqa (masalan kechagi) sana uchun shu kunlarda hech narsa yo'q — bo'sh ro'yxat
    kecha = (datetime.now(timezone.utc).date() - timedelta(days=1)).isoformat()
    bosh_javob = client.get(f"/api/v1/kiplar/smena/kunlik-jamlanma?sana={kecha}", headers=operator_headers)
    assert bosh_javob.status_code == 200
    assert bosh_javob.json()["mahsulotlar"] == []


def test_admin_sababli_ochirish(client, operator_headers, admin_headers, mahsulot_tola):
    partiya = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": 7}, headers=operator_headers
    ).json()
    kip = client.post("/api/v1/kiplar", json=_kip_yaratish_payload(partiya["id"]), headers=operator_headers).json()

    # sabab maydoni umuman berilmasa — validatsiya xatosi
    sababsiz = client.request("DELETE", f"/api/v1/kiplar/{kip['id']}", json={}, headers=admin_headers)
    assert sababsiz.status_code == 422

    ochirish = client.request(
        "DELETE", f"/api/v1/kiplar/{kip['id']}", json={"sabab": "Xato kiritilgan"}, headers=admin_headers
    )
    assert ochirish.status_code == 200
    assert ochirish.json()["holati"] == "bekor_qilingan"

    # Operator (admin bo'lmagan) o'chira olmaydi
    kip2 = client.post("/api/v1/kiplar", json=_kip_yaratish_payload(partiya["id"]), headers=operator_headers).json()
    rad_etildi = client.request(
        "DELETE", f"/api/v1/kiplar/{kip2['id']}", json={"sabab": "test"}, headers=operator_headers
    )
    assert rad_etildi.status_code == 403

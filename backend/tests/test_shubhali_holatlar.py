from datetime import date, datetime, timezone

from app.models.foydalanuvchi import Smena
from app.models.shubhali_holat import ShubhaliHolat, ShubhaliHolatStatusi


def test_royxat_faqat_admin(client, operator_headers):
    javob = client.get("/api/v1/shubhali-holatlar", headers=operator_headers)
    assert javob.status_code == 403


def test_royxat_filtr_va_tasdiqlash(client, db, admin_headers, admin):
    db.add(ShubhaliHolat(vaqt=datetime.now(timezone.utc), smena=Smena.A, ogirlik=5.0))
    db.add(ShubhaliHolat(vaqt=datetime.now(timezone.utc), smena=Smena.B, ogirlik=7.5))
    db.commit()

    hammasi = client.get("/api/v1/shubhali-holatlar", headers=admin_headers)
    assert hammasi.status_code == 200
    assert hammasi.json()["jami"] == 2

    faqat_a = client.get("/api/v1/shubhali-holatlar", params={"smena": "A"}, headers=admin_headers)
    assert faqat_a.json()["jami"] == 1
    assert faqat_a.json()["items"][0]["smena"] == "A"
    assert faqat_a.json()["items"][0]["korib_chiqqan_ism"] is None
    assert faqat_a.json()["items"][0]["tasdiqlangan"] is False

    hodisa_id = faqat_a.json()["items"][0]["id"]
    tasdiqlash = client.patch(f"/api/v1/shubhali-holatlar/{hodisa_id}/tasdiqla", headers=admin_headers)
    assert tasdiqlash.status_code == 200

    yangilangan = client.get("/api/v1/shubhali-holatlar", params={"smena": "A"}, headers=admin_headers)
    assert yangilangan.json()["items"][0]["korib_chiqqan_ism"] == admin.ism
    assert yangilangan.json()["items"][0]["holati"] == ShubhaliHolatStatusi.korib_chiqildi.value
    assert yangilangan.json()["items"][0]["tasdiqlangan"] is True

    faqat_tasdiqlanmagan = client.get(
        "/api/v1/shubhali-holatlar", params={"tasdiqlangan": False}, headers=admin_headers
    )
    assert faqat_tasdiqlanmagan.json()["jami"] == 1  # faqat B smenasidagi qoldi

    faqat_tasdiqlangan = client.get("/api/v1/shubhali-holatlar", params={"tasdiqlangan": True}, headers=admin_headers)
    assert faqat_tasdiqlangan.json()["jami"] == 1
    assert faqat_tasdiqlangan.json()["items"][0]["smena"] == "A"


def test_sana_filtri(client, db, admin_headers):
    db.add(ShubhaliHolat(vaqt=datetime.now(timezone.utc), smena=Smena.C, ogirlik=3.0))
    db.commit()

    ertaga = date.today().replace(day=min(date.today().day + 1, 28))
    javob = client.get("/api/v1/shubhali-holatlar", params={"sana_dan": ertaga.isoformat()}, headers=admin_headers)
    assert javob.json()["jami"] == 0


def test_operator_id_filtri(client, db, admin_headers, operator):
    db.add(ShubhaliHolat(vaqt=datetime.now(timezone.utc), smena=Smena.A, ogirlik=4.0, operator_id=operator.id))
    db.add(ShubhaliHolat(vaqt=datetime.now(timezone.utc), smena=Smena.B, ogirlik=6.0))
    db.commit()

    javob = client.get("/api/v1/shubhali-holatlar", params={"operator_id": operator.id}, headers=admin_headers)
    assert javob.json()["jami"] == 1
    assert javob.json()["items"][0]["operator_ism"] == operator.ism

    boshqasi = client.get(
        "/api/v1/shubhali-holatlar", params={"operator_id": operator.id + 999}, headers=admin_headers
    )
    assert boshqasi.json()["jami"] == 0


def test_sahifalash(client, db, admin_headers):
    for i in range(5):
        db.add(ShubhaliHolat(vaqt=datetime.now(timezone.utc), smena=Smena.D, ogirlik=1.0 + i))
    db.commit()

    birinchi_sahifa = client.get(
        "/api/v1/shubhali-holatlar", params={"smena": "D", "sahifa": 1, "sahifa_hajmi": 2}, headers=admin_headers
    )
    assert birinchi_sahifa.json()["jami"] == 5
    assert len(birinchi_sahifa.json()["items"]) == 2
    assert birinchi_sahifa.json()["sahifa"] == 1

    ikkinchi_sahifa = client.get(
        "/api/v1/shubhali-holatlar", params={"smena": "D", "sahifa": 2, "sahifa_hajmi": 2}, headers=admin_headers
    )
    assert len(ikkinchi_sahifa.json()["items"]) == 2

    uchinchi_sahifa = client.get(
        "/api/v1/shubhali-holatlar", params={"smena": "D", "sahifa": 3, "sahifa_hajmi": 2}, headers=admin_headers
    )
    assert len(uchinchi_sahifa.json()["items"]) == 1

    birinchi_idlar = {item["id"] for item in birinchi_sahifa.json()["items"]}
    ikkinchi_idlar = {item["id"] for item in ikkinchi_sahifa.json()["items"]}
    assert birinchi_idlar.isdisjoint(ikkinchi_idlar)

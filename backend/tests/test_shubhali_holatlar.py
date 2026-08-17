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

    hodisa_id = faqat_a.json()["items"][0]["id"]
    tasdiqlash = client.patch(f"/api/v1/shubhali-holatlar/{hodisa_id}/tasdiqla", headers=admin_headers)
    assert tasdiqlash.status_code == 200

    yangilangan = client.get("/api/v1/shubhali-holatlar", params={"smena": "A"}, headers=admin_headers)
    assert yangilangan.json()["items"][0]["korib_chiqqan_ism"] == admin.ism
    assert yangilangan.json()["items"][0]["holati"] == ShubhaliHolatStatusi.korib_chiqildi.value

    faqat_yangi = client.get("/api/v1/shubhali-holatlar", params={"holati": "yangi"}, headers=admin_headers)
    assert faqat_yangi.json()["jami"] == 1  # faqat B smenasidagi qoldi


def test_sana_filtri(client, db, admin_headers):
    db.add(ShubhaliHolat(vaqt=datetime.now(timezone.utc), smena=Smena.C, ogirlik=3.0))
    db.commit()

    ertaga = date.today().replace(day=min(date.today().day + 1, 28))
    javob = client.get("/api/v1/shubhali-holatlar", params={"sana_dan": ertaga.isoformat()}, headers=admin_headers)
    assert javob.json()["jami"] == 0

from datetime import date, datetime, timezone

from app.core.config import settings
from app.core.security import parolni_hash
from app.models.foydalanuvchi import Foydalanuvchi, Rol, Smena
from app.models.kip import Kip
from app.models.shubhali_holat import ShubhaliHolat, ShubhaliHolatStatusi


def test_stansiya_id_saqlanadi(client, stansiya):
    """Stansiya Agenti 'yuk saqlanmadi' hodisasini ro'yxatga olishda
    stansiya_id'ni ham yuboradi — shu qiymat to'g'ri saqlanishi kerak
    (ko'p-stansiyali arxitekturaga tayyorgarlik)."""
    javob = client.post(
        "/api/v1/shubhali-holatlar",
        data={
            "ogirlik": 5.5,
            "vaqt": datetime.now(timezone.utc).isoformat(),
            "smena": "A",
            "stansiya_id": stansiya.id,
        },
        headers={"X-Agent-Key": settings.AGENT_API_KEY},
    )

    assert javob.status_code == 201
    assert javob.json()["stansiya_id"] == stansiya.id


def test_stansiya_id_bermasa_null_saqlanadi(client):
    """stansiya_id ixtiyoriy — berilmasa xatosiz NULL sifatida saqlanadi
    (masalan agentda hali STANSIYA_ID sozlanmagan holatlar uchun)."""
    javob = client.post(
        "/api/v1/shubhali-holatlar",
        data={
            "ogirlik": 4.0,
            "vaqt": datetime.now(timezone.utc).isoformat(),
            "smena": "B",
        },
        headers={"X-Agent-Key": settings.AGENT_API_KEY},
    )

    assert javob.status_code == 201
    assert javob.json()["stansiya_id"] is None


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


def test_statistika_faqat_admin(client, operator_headers):
    javob = client.get("/api/v1/shubhali-holatlar/statistika", headers=operator_headers)
    assert javob.status_code == 403


def test_statistika_guruhlash(client, db, admin_headers, operator):
    ikkinchi_operator = Foydalanuvchi(
        ism="Smena B", login="smena_b", parol_hash=parolni_hash("parolB"), rol=Rol.operator, smena=Smena.B
    )
    db.add(ikkinchi_operator)
    db.commit()
    db.refresh(ikkinchi_operator)

    # tasdiqlangan hodisalar — statistikaga kirishi kerak
    db.add(
        ShubhaliHolat(
            vaqt=datetime.now(timezone.utc),
            smena=Smena.A,
            ogirlik=5.0,
            operator_id=operator.id,
            holati=ShubhaliHolatStatusi.korib_chiqildi,
        )
    )
    db.add(
        ShubhaliHolat(
            vaqt=datetime.now(timezone.utc),
            smena=Smena.A,
            ogirlik=6.0,
            operator_id=operator.id,
            holati=ShubhaliHolatStatusi.korib_chiqildi,
        )
    )
    db.add(
        ShubhaliHolat(
            vaqt=datetime.now(timezone.utc),
            smena=Smena.B,
            ogirlik=4.0,
            operator_id=ikkinchi_operator.id,
            holati=ShubhaliHolatStatusi.korib_chiqildi,
        )
    )
    # hali tasdiqlanmagan — statistikaga kirmasligi kerak
    db.add(ShubhaliHolat(vaqt=datetime.now(timezone.utc), smena=Smena.C, ogirlik=3.0, operator_id=operator.id))
    db.commit()

    javob = client.get("/api/v1/shubhali-holatlar/statistika", headers=admin_headers)
    assert javob.status_code == 200
    natija = javob.json()

    assert natija["smena_boyicha"] == {"A": 2, "B": 1, "C": 0, "D": 0}

    operator_boyicha = natija["operator_boyicha"]
    assert len(operator_boyicha) == 2
    assert operator_boyicha[0]["ism"] == operator.ism
    assert operator_boyicha[0]["soni"] == 2
    assert operator_boyicha[1]["ism"] == ikkinchi_operator.ism
    assert operator_boyicha[1]["soni"] == 1


def test_statistika_sana_filtri(client, db, admin_headers, operator):
    db.add(
        ShubhaliHolat(
            vaqt=datetime.now(timezone.utc),
            smena=Smena.A,
            ogirlik=5.0,
            operator_id=operator.id,
            holati=ShubhaliHolatStatusi.korib_chiqildi,
        )
    )
    db.commit()

    ertaga = date.today().replace(day=min(date.today().day + 1, 28))
    javob = client.get(
        "/api/v1/shubhali-holatlar/statistika", params={"sana_dan": ertaga.isoformat()}, headers=admin_headers
    )
    assert javob.status_code == 200
    natija = javob.json()
    assert natija["smena_boyicha"] == {"A": 0, "B": 0, "C": 0, "D": 0}
    assert natija["operator_boyicha"] == []


# ---------------------------------------------------------------------------
# AUDIT TUZATISHI (UX yangilash): operator endi hodisadan bloklanmaydi —
# admin panel orqali IKKITA aniq amal bilan hal qilinadi:
#   - PATCH /{id}/tasdiqla ("Ko'rdim") — soxta signal, hech narsa yaratilmaydi
#   - POST /{id}/saqlash ("Saqlash") — HAQIQIY bo'lgan, mahsulot/partiya
#     qo'lda tanlanib HAQIQIY Kip yaratiladi
# ---------------------------------------------------------------------------


def _partiya_yarat(client, operator_headers, mahsulot_kodi: str, raqami: int) -> dict:
    return client.post(
        "/api/v1/partiyalar",
        json={"mahsulot_kodi": mahsulot_kodi, "partiya_raqami": raqami},
        headers=operator_headers,
    ).json()


def test_tasdiqla_kip_yaratmaydi(client, db, admin_headers):
    """"Ko'rdim" — hodisani yopadi, lekin HECH QANDAY Kip yaratmaydi (soxta
    signal ma'nosida)."""
    hodisa = ShubhaliHolat(vaqt=datetime.now(timezone.utc), smena=Smena.A, ogirlik=5.0)
    db.add(hodisa)
    db.commit()
    db.refresh(hodisa)

    javob = client.patch(f"/api/v1/shubhali-holatlar/{hodisa.id}/tasdiqla", headers=admin_headers)
    assert javob.status_code == 200
    assert javob.json()["holati"] == ShubhaliHolatStatusi.korib_chiqildi.value

    assert db.query(Kip).count() == 0


def test_saqlash_admin_kip_yaratadi(client, db, admin, admin_headers, operator_headers, mahsulot_tola):
    """"Saqlash" — admin mahsulot/partiya tanlab yuboradi, tizim HODISANING
    OG'IRLIGI bilan HAQIQIY Kip yozuvi yaratadi va hodisani yopadi."""
    partiya = _partiya_yarat(client, operator_headers, "tola", 700)

    hodisa = ShubhaliHolat(vaqt=datetime.now(timezone.utc), smena=Smena.B, ogirlik=123.45)
    db.add(hodisa)
    db.commit()
    db.refresh(hodisa)

    javob = client.post(
        f"/api/v1/shubhali-holatlar/{hodisa.id}/saqlash",
        json={"mahsulot_kodi": "tola", "partiya_raqami": 700},
        headers=admin_headers,
    )
    assert javob.status_code == 200
    kip_javob = javob.json()
    assert kip_javob["ogirlik"] == 123.45
    assert kip_javob["smena"] == "B"
    assert kip_javob["partiya_id"] == partiya["id"]
    assert kip_javob["kip_raqami"] == 1
    assert kip_javob["holati"] == "aktiv"
    # Hodisada operator_id yo'q edi — admin QO'LDA hal qilayotgani uchun
    # yaratilgan kipning operatori sifatida ADMINNING o'zi yoziladi.
    assert kip_javob["operator_id"] == admin.id

    db.refresh(hodisa)
    assert hodisa.holati == ShubhaliHolatStatusi.korib_chiqildi
    assert hodisa.korib_chiqqan_id == admin.id
    assert hodisa.korib_chiqilgan_vaqt is not None

    assert db.query(Kip).count() == 1


def test_saqlash_mavjud_operatorni_saqlab_qoladi(client, db, admin_headers, operator, operator_headers, mahsulot_tola):
    """Agar hodisada (kamdan-kam holatda) operator_id BOR bo'lsa — yangi
    Kip o'sha haqiqiy operatorga yoziladi, admin bilan almashtirilmaydi."""
    partiya = _partiya_yarat(client, operator_headers, "tola", 701)
    hodisa = ShubhaliHolat(vaqt=datetime.now(timezone.utc), smena=Smena.A, ogirlik=88.0, operator_id=operator.id)
    db.add(hodisa)
    db.commit()
    db.refresh(hodisa)

    javob = client.post(
        f"/api/v1/shubhali-holatlar/{hodisa.id}/saqlash",
        json={"mahsulot_kodi": "tola", "partiya_raqami": 701},
        headers=admin_headers,
    )
    assert javob.status_code == 200
    assert javob.json()["operator_id"] == operator.id
    assert partiya["id"]  # partiya yaratilgani sog'lomlik tekshiruvi


def test_saqlash_operatorga_taqiqlangan(client, db, operator_headers):
    hodisa = ShubhaliHolat(vaqt=datetime.now(timezone.utc), smena=Smena.A, ogirlik=5.0)
    db.add(hodisa)
    db.commit()
    db.refresh(hodisa)

    javob = client.post(
        f"/api/v1/shubhali-holatlar/{hodisa.id}/saqlash",
        json={"mahsulot_kodi": "tola", "partiya_raqami": 1},
        headers=operator_headers,
    )
    assert javob.status_code == 403


def test_saqlash_notogri_id_404(client, admin_headers):
    javob = client.post(
        "/api/v1/shubhali-holatlar/999999/saqlash",
        json={"mahsulot_kodi": "tola", "partiya_raqami": 1},
        headers=admin_headers,
    )
    assert javob.status_code == 404


def test_saqlash_notogri_mahsulot_400(client, db, admin_headers):
    hodisa = ShubhaliHolat(vaqt=datetime.now(timezone.utc), smena=Smena.A, ogirlik=5.0)
    db.add(hodisa)
    db.commit()
    db.refresh(hodisa)

    javob = client.post(
        f"/api/v1/shubhali-holatlar/{hodisa.id}/saqlash",
        json={"mahsulot_kodi": "mavjud_emas", "partiya_raqami": 1},
        headers=admin_headers,
    )
    assert javob.status_code == 400


def test_saqlash_notogri_partiya_400(client, db, admin_headers, mahsulot_tola):
    hodisa = ShubhaliHolat(vaqt=datetime.now(timezone.utc), smena=Smena.A, ogirlik=5.0)
    db.add(hodisa)
    db.commit()
    db.refresh(hodisa)

    javob = client.post(
        f"/api/v1/shubhali-holatlar/{hodisa.id}/saqlash",
        json={"mahsulot_kodi": "tola", "partiya_raqami": 999999},
        headers=admin_headers,
    )
    assert javob.status_code == 400


def test_saqlash_yopiq_partiyaga_400(client, db, admin_headers, operator_headers, mahsulot_tola):
    partiya = _partiya_yarat(client, operator_headers, "tola", 702)
    client.patch(f"/api/v1/partiyalar/{partiya['id']}/yopish", headers=operator_headers)

    hodisa = ShubhaliHolat(vaqt=datetime.now(timezone.utc), smena=Smena.A, ogirlik=5.0)
    db.add(hodisa)
    db.commit()
    db.refresh(hodisa)

    javob = client.post(
        f"/api/v1/shubhali-holatlar/{hodisa.id}/saqlash",
        json={"mahsulot_kodi": "tola", "partiya_raqami": 702},
        headers=admin_headers,
    )
    assert javob.status_code == 400


def test_saqlash_smena_yoq_bolsa_400(client, db, admin_headers, operator_headers, mahsulot_tola):
    partiya = _partiya_yarat(client, operator_headers, "tola", 703)
    hodisa = ShubhaliHolat(vaqt=datetime.now(timezone.utc), smena=None, ogirlik=5.0)
    db.add(hodisa)
    db.commit()
    db.refresh(hodisa)

    javob = client.post(
        f"/api/v1/shubhali-holatlar/{hodisa.id}/saqlash",
        json={"mahsulot_kodi": "tola", "partiya_raqami": partiya["partiya_raqami"]},
        headers=admin_headers,
    )
    assert javob.status_code == 400


def test_saqlash_allaqachon_korib_chiqilgan_409(client, db, admin_headers, operator_headers, mahsulot_tola):
    partiya = _partiya_yarat(client, operator_headers, "tola", 704)
    hodisa = ShubhaliHolat(
        vaqt=datetime.now(timezone.utc),
        smena=Smena.A,
        ogirlik=5.0,
        holati=ShubhaliHolatStatusi.korib_chiqildi,
    )
    db.add(hodisa)
    db.commit()
    db.refresh(hodisa)

    javob = client.post(
        f"/api/v1/shubhali-holatlar/{hodisa.id}/saqlash",
        json={"mahsulot_kodi": "tola", "partiya_raqami": partiya["partiya_raqami"]},
        headers=admin_headers,
    )
    assert javob.status_code == 409
    assert db.query(Kip).count() == 0


def test_saqlash_ikkinchi_marta_ikkinchi_kip_yaratmaydi(client, db, admin_headers, operator_headers, mahsulot_tola):
    """Bitta hodisadan faqat BITTA Kip yaratilishi mumkin — ikkinchi
    "Saqlash" urinishi (masalan qo'sh-bosish) 409 bilan rad etiladi."""
    partiya = _partiya_yarat(client, operator_headers, "tola", 705)
    hodisa = ShubhaliHolat(vaqt=datetime.now(timezone.utc), smena=Smena.A, ogirlik=5.0)
    db.add(hodisa)
    db.commit()
    db.refresh(hodisa)

    tana = {"mahsulot_kodi": "tola", "partiya_raqami": partiya["partiya_raqami"]}
    birinchi = client.post(f"/api/v1/shubhali-holatlar/{hodisa.id}/saqlash", json=tana, headers=admin_headers)
    assert birinchi.status_code == 200

    ikkinchi = client.post(f"/api/v1/shubhali-holatlar/{hodisa.id}/saqlash", json=tana, headers=admin_headers)
    assert ikkinchi.status_code == 409

    assert db.query(Kip).count() == 1

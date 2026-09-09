import uuid
from datetime import date, datetime, timezone

from app.models.foydalanuvchi import Smena
from app.models.kip import Kip, KipHolati
from app.models.partiya import Partiya, PartiyaHolati


def _partiya_yarat(db, mahsulot_id, raqami):
    partiya = Partiya(mahsulot_id=mahsulot_id, partiya_raqami=raqami, holati=PartiyaHolati.ochiq)
    db.add(partiya)
    db.commit()
    db.refresh(partiya)
    return partiya


def _kip_yarat(db, partiya_id, kip_raqami, ogirlik, smena, sana: date, operator_id):
    vaqt = datetime(sana.year, sana.month, sana.day, 10, 0, tzinfo=timezone.utc)
    kip = Kip(
        mijoz_id=str(uuid.uuid4()),
        partiya_id=partiya_id,
        kip_raqami=kip_raqami,
        ogirlik=ogirlik,
        smena=smena,
        operator_id=operator_id,
        mahalliy_vaqt=vaqt,
        vaqt=vaqt,
        holati=KipHolati.aktiv,
    )
    db.add(kip)
    db.commit()
    return kip


def test_dashboard_notogri_davr_xato_beradi(client, admin_headers):
    javob = client.get("/api/v1/dashboard", params={"davr": "yillik"}, headers=admin_headers)
    assert javob.status_code == 400


def test_dashboard_standart_davr_kunlik(client, admin_headers):
    javob = client.get("/api/v1/dashboard", headers=admin_headers)
    assert javob.status_code == 200
    tana = javob.json()
    assert tana["davr"] == "kunlik"
    assert tana["boshlanish_sanasi"] == date.today().isoformat()
    assert tana["tugash_sanasi"] == date.today().isoformat()


def test_dashboard_davr_parametri_kiplarni_filtrlaydi(client, db, admin_headers, operator, mahsulot_tola):
    partiya = _partiya_yarat(db, mahsulot_tola.id, 910)
    # Bugungi kip — barcha davrlarda ko'rinishi kerak
    _kip_yarat(db, partiya.id, 1, 100.0, Smena.A, date.today(), operator.id)
    # Juda eski kip — kunlik/haftalik/oylik/mavsumning barchasidan tashqarida
    _kip_yarat(db, partiya.id, 2, 50.0, Smena.A, date(2019, 1, 1), operator.id)

    kunlik = client.get("/api/v1/dashboard", params={"davr": "kunlik"}, headers=admin_headers).json()
    assert kunlik["jami_soni"] == 1
    assert kunlik["jami_kg"] == 100.0
    assert kunlik["mahsulotlar"][0]["mahsulot_kodi"] == "tola"
    assert any(s["smena"] == "A" and s["soni"] == 1 for s in kunlik["smenalar"])

    # Standart holatda (davr berilmasa) ham xuddi shu natija (default kunlik)
    standart = client.get("/api/v1/dashboard", headers=admin_headers).json()
    assert standart["jami_soni"] == 1


def test_dashboard_ochiq_partiyalar_va_shubhali_holatlar_davrga_bogliq_emas(
    client, db, admin_headers, mahsulot_tola
):
    _partiya_yarat(db, mahsulot_tola.id, 920)

    kunlik = client.get("/api/v1/dashboard", params={"davr": "kunlik"}, headers=admin_headers).json()
    mavsum = client.get("/api/v1/dashboard", params={"davr": "mavsum"}, headers=admin_headers).json()

    assert kunlik["ochiq_partiyalar_soni"] == mavsum["ochiq_partiyalar_soni"] >= 1
    assert kunlik["tasdiqlanmagan_shubhali_holatlar_soni"] == mavsum["tasdiqlanmagan_shubhali_holatlar_soni"]


def test_dashboard_operator_kira_olmaydi(client, operator_headers):
    javob = client.get("/api/v1/dashboard", headers=operator_headers)
    assert javob.status_code == 403


def test_dashboard_tahrirlangan_kip_hisoblanadi_bekor_hisoblanmaydi(
    client, db, admin_headers, operator, mahsulot_tola
):
    partiya = _partiya_yarat(db, mahsulot_tola.id, 930)
    _kip_yarat(db, partiya.id, 1, 100.0, Smena.A, date.today(), operator.id)
    tahrirlangan = _kip_yarat(db, partiya.id, 2, 40.0, Smena.A, date.today(), operator.id)
    tahrirlangan.holati = KipHolati.tahrirlangan
    bekor = _kip_yarat(db, partiya.id, 3, 999.0, Smena.A, date.today(), operator.id)
    bekor.holati = KipHolati.bekor_qilingan
    db.commit()

    kunlik = client.get("/api/v1/dashboard", params={"davr": "kunlik"}, headers=admin_headers).json()
    assert kunlik["jami_soni"] == 2
    assert kunlik["jami_kg"] == 140.0
    smena_a = next(s for s in kunlik["smenalar"] if s["smena"] == "A")
    assert smena_a["soni"] == 2
    assert smena_a["jami_kg"] == 140.0

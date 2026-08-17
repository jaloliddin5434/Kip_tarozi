import uuid
from datetime import date, datetime, timedelta, timezone

from app.models.foydalanuvchi import Smena
from app.models.kip import Kip, KipHolati
from app.models.mahsulot import Mahsulot
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


def test_jamlanma_smena_filtri_ishlaydi(client, db, admin_headers, operator, mahsulot_tola):
    partiya = _partiya_yarat(db, mahsulot_tola.id, 700)
    _kip_yarat(db, partiya.id, 1, 100.0, Smena.A, date.today(), operator.id)
    _kip_yarat(db, partiya.id, 2, 50.0, Smena.B, date.today(), operator.id)

    jami = client.get("/api/v1/statistika/jamlanma", params={"davr": "kunlik"}, headers=admin_headers).json()
    assert jami["jami_soni"] == 2
    assert jami["jami_kg"] == 150.0

    faqat_a = client.get(
        "/api/v1/statistika/jamlanma", params={"davr": "kunlik", "smena": "A"}, headers=admin_headers
    ).json()
    assert faqat_a["jami_soni"] == 1
    assert faqat_a["jami_kg"] == 100.0


def test_jamlanma_ixtiyoriy_sana_qabul_qiladi(client, db, admin_headers, operator, mahsulot_tola):
    otgan_kun = date.today() - timedelta(days=5)
    partiya = _partiya_yarat(db, mahsulot_tola.id, 705)
    _kip_yarat(db, partiya.id, 1, 120.0, Smena.A, otgan_kun, operator.id)
    # bugungi kun uchun mos kelmasligi kerak bo'lgan yozuv
    _kip_yarat(db, partiya.id, 2, 999.0, Smena.A, date.today(), operator.id)

    javob = client.get(
        "/api/v1/statistika/jamlanma",
        params={"davr": "kunlik", "sana": otgan_kun.isoformat()},
        headers=admin_headers,
    ).json()
    assert javob["boshlanish_sanasi"] == otgan_kun.isoformat()
    assert javob["tugash_sanasi"] == otgan_kun.isoformat()
    assert javob["jami_soni"] == 1
    assert javob["jami_kg"] == 120.0


def test_smena_boyicha_mahsulot_kodi_filtrlaydi(client, db, admin_headers, operator, mahsulot_tola):
    lint = Mahsulot(kod="lint", nomi="Lint")
    db.add(lint)
    db.commit()

    tola_partiya = _partiya_yarat(db, mahsulot_tola.id, 701)
    lint_partiya = _partiya_yarat(db, lint.id, 702)

    _kip_yarat(db, tola_partiya.id, 1, 100.0, Smena.A, date.today(), operator.id)
    _kip_yarat(db, lint_partiya.id, 1, 40.0, Smena.B, date.today(), operator.id)

    barchasi = client.get(
        "/api/v1/statistika/smena-boyicha", params={"davr": "kunlik"}, headers=admin_headers
    ).json()
    jami_soni = sum(s["soni"] for s in barchasi)
    assert jami_soni == 2

    faqat_tola = client.get(
        "/api/v1/statistika/smena-boyicha",
        params={"davr": "kunlik", "mahsulot_kodi": "tola"},
        headers=admin_headers,
    ).json()
    assert len(faqat_tola) == 1
    assert faqat_tola[0]["smena"] == "A"
    assert faqat_tola[0]["soni"] == 1
    assert faqat_tola[0]["jami_kg"] == 100.0

    faqat_lint = client.get(
        "/api/v1/statistika/smena-boyicha",
        params={"davr": "kunlik", "mahsulot_kodi": "lint"},
        headers=admin_headers,
    ).json()
    assert len(faqat_lint) == 1
    assert faqat_lint[0]["smena"] == "B"
    assert faqat_lint[0]["jami_kg"] == 40.0


def test_smena_boyicha_mavjud_bolmagan_mahsulot_kodi_bosh_royxat(client, admin_headers):
    javob = client.get(
        "/api/v1/statistika/smena-boyicha",
        params={"davr": "kunlik", "mahsulot_kodi": "mavjud_emas"},
        headers=admin_headers,
    )
    assert javob.status_code == 200
    assert javob.json() == []


def test_statistika_operator_kira_olmaydi(client, operator_headers):
    javob = client.get("/api/v1/statistika/jamlanma", headers=operator_headers)
    assert javob.status_code == 403

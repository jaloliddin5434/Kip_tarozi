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


def _operator_yarat(db, ism, login, smena):
    from app.core.security import parolni_hash
    from app.models.foydalanuvchi import Foydalanuvchi, Rol

    foydalanuvchi = Foydalanuvchi(
        ism=ism, login=login, parol_hash=parolni_hash("parol123"), rol=Rol.operator, smena=smena
    )
    db.add(foydalanuvchi)
    db.commit()
    db.refresh(foydalanuvchi)
    return foydalanuvchi


def test_rekordlar_eng_yaxshi_smena_va_operator_davr_boyicha(client, db, admin_headers, mahsulot_tola):
    op_a = _operator_yarat(db, "Operator A", "op_a", Smena.A)
    op_b = _operator_yarat(db, "Operator B", "op_b", Smena.B)
    partiya = _partiya_yarat(db, mahsulot_tola.id, 800)

    bugun = date.today()
    # Smena B — kg bo'yicha eng ko'p (300), lekin atigi 2 ta kip
    _kip_yarat(db, partiya.id, 1, 150.0, Smena.B, bugun, op_b.id)
    _kip_yarat(db, partiya.id, 2, 150.0, Smena.B, bugun, op_b.id)
    # Smena A — kg kamroq (120), lekin 3 ta kip (soni bo'yicha eng ko'p)
    _kip_yarat(db, partiya.id, 3, 40.0, Smena.A, bugun, op_a.id)
    _kip_yarat(db, partiya.id, 4, 40.0, Smena.A, bugun, op_a.id)
    _kip_yarat(db, partiya.id, 5, 40.0, Smena.A, bugun, op_a.id)

    javob = client.get("/api/v1/statistika/rekordlar", params={"davr": "kunlik"}, headers=admin_headers).json()

    assert javob["eng_yaxshi_smena"]["smena"] == "B"
    assert javob["eng_yaxshi_smena"]["jami_kg"] == 300.0
    assert javob["eng_yaxshi_operator"]["login"] == "op_a"
    assert javob["eng_yaxshi_operator"]["soni"] == 3


def test_rekordlar_eng_yuqori_kunlik_yigim_barcha_vaqt_boyicha(client, db, admin_headers, operator, mahsulot_tola):
    partiya = _partiya_yarat(db, mahsulot_tola.id, 801)

    rekord_kun = date.today() - timedelta(days=40)  # har qanday davrdan tashqarida
    _kip_yarat(db, partiya.id, 1, 500.0, Smena.A, rekord_kun, operator.id)
    _kip_yarat(db, partiya.id, 2, 400.0, Smena.B, rekord_kun, operator.id)
    # bugun — kamroq
    _kip_yarat(db, partiya.id, 3, 100.0, Smena.A, date.today(), operator.id)

    for davr in ("kunlik", "haftalik", "oylik", "mavsum"):
        javob = client.get("/api/v1/statistika/rekordlar", params={"davr": davr}, headers=admin_headers).json()
        assert javob["eng_yuqori_kunlik_yigim"]["sana"] == rekord_kun.isoformat()
        assert javob["eng_yuqori_kunlik_yigim"]["jami_kg"] == 900.0


def test_rekordlar_bekor_qilingan_kip_hisobga_olinmaydi(client, db, admin_headers, operator, mahsulot_tola):
    partiya = _partiya_yarat(db, mahsulot_tola.id, 802)
    kip = _kip_yarat(db, partiya.id, 1, 999.0, Smena.A, date.today(), operator.id)
    kip.holati = KipHolati.bekor_qilingan
    db.commit()

    javob = client.get("/api/v1/statistika/rekordlar", params={"davr": "kunlik"}, headers=admin_headers).json()
    assert javob["eng_yaxshi_smena"] is None
    assert javob["eng_yaxshi_operator"] is None
    assert javob["eng_yuqori_kunlik_yigim"] is None


def test_rekordlar_malumot_yoq_bosh_holat(client, admin_headers):
    javob = client.get("/api/v1/statistika/rekordlar", params={"davr": "mavsum"}, headers=admin_headers).json()
    assert javob["eng_yaxshi_smena"] is None
    assert javob["eng_yaxshi_operator"] is None
    assert javob["eng_yuqori_kunlik_yigim"] is None


def test_rekordlar_operator_kira_olmaydi(client, operator_headers):
    javob = client.get("/api/v1/statistika/rekordlar", params={"davr": "kunlik"}, headers=operator_headers)
    assert javob.status_code == 403

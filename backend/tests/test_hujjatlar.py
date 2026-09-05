import uuid
from datetime import datetime, timezone

from app.core.security import parolni_hash
from app.models.foydalanuvchi import Foydalanuvchi, Rol, Smena
from app.models.kip import Kip, KipHolati
from app.models.mahsulot import Mahsulot
from app.models.partiya import Partiya, PartiyaHolati


def _partiya_yarat(db, mahsulot_id, raqami):
    partiya = Partiya(mahsulot_id=mahsulot_id, partiya_raqami=raqami, holati=PartiyaHolati.ochiq)
    db.add(partiya)
    db.commit()
    db.refresh(partiya)
    return partiya


def _kip_yarat(db, partiya_id, kip_raqami, ogirlik, smena, operator_id, holati=KipHolati.aktiv):
    vaqt = datetime.now(timezone.utc)
    kip = Kip(
        mijoz_id=str(uuid.uuid4()),
        partiya_id=partiya_id,
        kip_raqami=kip_raqami,
        ogirlik=ogirlik,
        smena=smena,
        operator_id=operator_id,
        mahalliy_vaqt=vaqt,
        vaqt=vaqt,
        holati=holati,
    )
    db.add(kip)
    db.commit()
    return kip


def test_kiplar_royxati_holati_filtri_ishlaydi(client, db, admin_headers, operator, mahsulot_tola):
    partiya = _partiya_yarat(db, mahsulot_tola.id, 800)
    _kip_yarat(db, partiya.id, 1, 100.0, Smena.A, operator.id, holati=KipHolati.aktiv)
    _kip_yarat(db, partiya.id, 2, 110.0, Smena.A, operator.id, holati=KipHolati.tahrirlangan)
    _kip_yarat(db, partiya.id, 3, 120.0, Smena.A, operator.id, holati=KipHolati.bekor_qilingan)

    barchasi = client.get("/api/v1/hujjatlar/kiplar", headers=admin_headers).json()
    assert barchasi["jami"] == 3

    faqat_tahrirlangan = client.get(
        "/api/v1/hujjatlar/kiplar", params={"holati": "tahrirlangan"}, headers=admin_headers
    ).json()
    assert faqat_tahrirlangan["jami"] == 1
    assert faqat_tahrirlangan["items"][0]["holati"] == "tahrirlangan"

    faqat_bekor = client.get(
        "/api/v1/hujjatlar/kiplar", params={"holati": "bekor_qilingan"}, headers=admin_headers
    ).json()
    assert faqat_bekor["jami"] == 1
    assert faqat_bekor["items"][0]["holati"] == "bekor_qilingan"

    faqat_aktiv = client.get("/api/v1/hujjatlar/kiplar", params={"holati": "aktiv"}, headers=admin_headers).json()
    assert faqat_aktiv["jami"] == 1
    assert faqat_aktiv["items"][0]["holati"] == "aktiv"


def test_kiplar_royxati_notogri_holati_400(client, admin_headers):
    javob = client.get("/api/v1/hujjatlar/kiplar", params={"holati": "notogri"}, headers=admin_headers)
    assert javob.status_code == 422


def test_kiplar_royxati_qidiruv_operator_ismi_boyicha(client, db, admin_headers, operator, mahsulot_tola):
    boshqa_operator = Foydalanuvchi(
        ism="Dilnoza Yusupova",
        login="dilnoza_qidiruv",
        parol_hash=parolni_hash("parolD"),
        rol=Rol.operator,
        smena=Smena.B,
    )
    db.add(boshqa_operator)
    db.commit()
    db.refresh(boshqa_operator)

    partiya = _partiya_yarat(db, mahsulot_tola.id, 810)
    _kip_yarat(db, partiya.id, 1, 100.0, Smena.A, operator.id)
    _kip_yarat(db, partiya.id, 2, 105.0, Smena.B, boshqa_operator.id)

    javob = client.get("/api/v1/hujjatlar/kiplar", params={"qidiruv": "dilnoza"}, headers=admin_headers).json()
    assert javob["jami"] == 1
    assert javob["items"][0]["operator_ism"] == "Dilnoza Yusupova"

    javob_katta = client.get("/api/v1/hujjatlar/kiplar", params={"qidiruv": "DILNOZA"}, headers=admin_headers).json()
    assert javob_katta["jami"] == 1


def test_kiplar_royxati_qidiruv_partiya_raqami_boyicha(client, db, admin_headers, operator, mahsulot_tola):
    partiya_maxsus = _partiya_yarat(db, mahsulot_tola.id, 8123)
    partiya_oddiy = _partiya_yarat(db, mahsulot_tola.id, 555)
    _kip_yarat(db, partiya_maxsus.id, 1, 100.0, Smena.A, operator.id)
    _kip_yarat(db, partiya_oddiy.id, 1, 105.0, Smena.A, operator.id)

    javob = client.get("/api/v1/hujjatlar/kiplar", params={"qidiruv": "812"}, headers=admin_headers).json()
    assert javob["jami"] == 1
    assert javob["items"][0]["partiya_raqami"] == 8123


def test_kiplar_royxati_qidiruv_mos_kelmasa_bosh_royxat(client, db, admin_headers, operator, mahsulot_tola):
    partiya = _partiya_yarat(db, mahsulot_tola.id, 820)
    _kip_yarat(db, partiya.id, 1, 100.0, Smena.A, operator.id)

    javob = client.get(
        "/api/v1/hujjatlar/kiplar", params={"qidiruv": "mavjud_emas_qidiruv"}, headers=admin_headers
    ).json()
    assert javob["jami"] == 0


def test_kiplar_royxati_mahsulot_kodi_filtri_ishlaydi(client, db, admin_headers, operator, mahsulot_tola):
    lint = Mahsulot(kod="lint", nomi="Lint")
    db.add(lint)
    db.commit()
    db.refresh(lint)

    tola_partiya = _partiya_yarat(db, mahsulot_tola.id, 830)
    lint_partiya = _partiya_yarat(db, lint.id, 831)
    _kip_yarat(db, tola_partiya.id, 1, 100.0, Smena.A, operator.id)
    _kip_yarat(db, lint_partiya.id, 1, 90.0, Smena.A, operator.id)

    faqat_tola = client.get(
        "/api/v1/hujjatlar/kiplar", params={"mahsulot_kodi": "tola"}, headers=admin_headers
    ).json()
    assert faqat_tola["jami"] == 1
    assert faqat_tola["items"][0]["mahsulot_kodi"] == "tola"

    faqat_lint = client.get(
        "/api/v1/hujjatlar/kiplar", params={"mahsulot_kodi": "lint"}, headers=admin_headers
    ).json()
    assert faqat_lint["jami"] == 1
    assert faqat_lint["items"][0]["mahsulot_kodi"] == "lint"

    filtrsiz = client.get("/api/v1/hujjatlar/kiplar", headers=admin_headers).json()
    assert filtrsiz["jami"] == 2


def test_kiplar_royxati_kip_raqami_filtri_bir_nechta_partiyada(client, db, admin_headers, operator, mahsulot_tola):
    """Kip raqami partiya ichida ketma-ket beriladi, shuning uchun turli
    partiyalarda bir xil kip_raqami takrorlanishi normal holat — filtr
    shu kip_raqamiga mos KELGAN BARCHA partiyalardagi yozuvlarni qaytarishi
    kerak, faqat bittasini emas."""
    partiya_1 = _partiya_yarat(db, mahsulot_tola.id, 840)
    partiya_2 = _partiya_yarat(db, mahsulot_tola.id, 841)
    _kip_yarat(db, partiya_1.id, 1, 100.0, Smena.A, operator.id)
    _kip_yarat(db, partiya_2.id, 1, 105.0, Smena.A, operator.id)
    _kip_yarat(db, partiya_1.id, 2, 110.0, Smena.A, operator.id)

    javob = client.get("/api/v1/hujjatlar/kiplar", params={"kip_raqami": 1}, headers=admin_headers).json()
    assert javob["jami"] == 2
    partiya_raqamlari = {item["partiya_raqami"] for item in javob["items"]}
    assert partiya_raqamlari == {840, 841}

    javob_2 = client.get("/api/v1/hujjatlar/kiplar", params={"kip_raqami": 2}, headers=admin_headers).json()
    assert javob_2["jami"] == 1
    assert javob_2["items"][0]["partiya_raqami"] == 840

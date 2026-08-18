import uuid
from datetime import date, datetime, timedelta, timezone

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


def _kip_yarat(db, partiya_id, kip_raqami, ogirlik, smena, operator_id, sana=None, holati=KipHolati.aktiv):
    sana = sana or date.today()
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
        holati=holati,
    )
    db.add(kip)
    db.commit()
    db.refresh(kip)
    return kip


def test_smena_royxati_faqat_oz_smenasi_va_mahsuloti(client, db, operator_headers, operator, mahsulot_tola):
    lint = Mahsulot(kod="lint", nomi="Lint")
    db.add(lint)
    db.commit()

    boshqa_operator = Foydalanuvchi(
        ism="Smena B", login="smena_b_royxat", parol_hash=parolni_hash("parolB"), rol=Rol.operator, smena=Smena.B
    )
    db.add(boshqa_operator)
    db.commit()
    db.refresh(boshqa_operator)

    tola_partiya = _partiya_yarat(db, mahsulot_tola.id, 950)
    lint_partiya = _partiya_yarat(db, lint.id, 951)

    kip1 = _kip_yarat(db, tola_partiya.id, 1, 100.0, Smena.A, operator.id)
    kip2 = _kip_yarat(db, tola_partiya.id, 2, 110.0, Smena.A, operator.id)
    _kip_yarat(db, lint_partiya.id, 1, 50.0, Smena.A, operator.id)  # boshqa mahsulot — chiqmasligi kerak
    _kip_yarat(db, tola_partiya.id, 3, 120.0, Smena.B, boshqa_operator.id)  # boshqa smena — chiqmasligi kerak

    javob = client.get(
        "/api/v1/kiplar/smena/royxat", params={"mahsulot_kodi": "tola"}, headers=operator_headers
    )
    assert javob.status_code == 200
    natija = javob.json()
    assert len(natija) == 2
    kip_raqamlari = {yozuv["kip_raqami"] for yozuv in natija}
    assert kip_raqamlari == {1, 2}
    # eng yangisi birinchi
    assert natija[0]["kip_raqami"] == 2
    assert natija[0]["ogirlik"] == 110.0
    assert natija[0]["holati"] == "aktiv"
    assert natija[0]["id"] == kip2.id
    assert natija[1]["id"] == kip1.id


def test_smena_royxati_otgan_kunlar_korinmaydi(client, db, operator_headers, operator, mahsulot_tola):
    partiya = _partiya_yarat(db, mahsulot_tola.id, 952)
    kecha = date.today() - timedelta(days=1)
    _kip_yarat(db, partiya.id, 1, 100.0, Smena.A, operator.id, sana=kecha)
    _kip_yarat(db, partiya.id, 2, 100.0, Smena.A, operator.id)

    javob = client.get(
        "/api/v1/kiplar/smena/royxat", params={"mahsulot_kodi": "tola"}, headers=operator_headers
    ).json()
    assert len(javob) == 1
    assert javob[0]["kip_raqami"] == 2


def test_smena_royxati_bekor_qilingan_kip_holati_bilan_korinadi(client, db, operator_headers, operator, mahsulot_tola):
    partiya = _partiya_yarat(db, mahsulot_tola.id, 953)
    _kip_yarat(db, partiya.id, 1, 100.0, Smena.A, operator.id, holati=KipHolati.bekor_qilingan)

    javob = client.get(
        "/api/v1/kiplar/smena/royxat", params={"mahsulot_kodi": "tola"}, headers=operator_headers
    ).json()
    assert len(javob) == 1
    assert javob[0]["holati"] == "bekor_qilingan"


def test_smena_royxati_admin_kira_olmaydi(client, admin_headers):
    javob = client.get("/api/v1/kiplar/smena/royxat", params={"mahsulot_kodi": "tola"}, headers=admin_headers)
    assert javob.status_code == 403

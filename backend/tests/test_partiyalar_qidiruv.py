from app.models.mahsulot import Mahsulot
from app.models.partiya import Partiya, PartiyaHolati


def _partiya_yarat(db, mahsulot_id, raqami, holati=PartiyaHolati.ochiq, xaridor=None):
    partiya = Partiya(mahsulot_id=mahsulot_id, partiya_raqami=raqami, holati=holati, xaridor=xaridor)
    db.add(partiya)
    db.commit()
    db.refresh(partiya)
    return partiya


def test_qidiruv_mahsulot_nomi_boyicha(client, db, admin_headers, mahsulot_tola):
    lint = Mahsulot(kod="lint_q", nomi="Lint")
    db.add(lint)
    db.commit()

    _partiya_yarat(db, mahsulot_tola.id, 601)
    _partiya_yarat(db, lint.id, 602)

    javob = client.get("/api/v1/partiyalar", params={"qidiruv": mahsulot_tola.nomi}, headers=admin_headers)
    assert javob.status_code == 200
    natija = javob.json()
    raqamlar = {item["partiya_raqami"] for item in natija["items"]}
    assert 601 in raqamlar
    assert 602 not in raqamlar


def test_qidiruv_partiya_raqami_boyicha(client, db, admin_headers, mahsulot_tola):
    _partiya_yarat(db, mahsulot_tola.id, 60301)
    _partiya_yarat(db, mahsulot_tola.id, 700)

    javob = client.get("/api/v1/partiyalar", params={"qidiruv": "60301"}, headers=admin_headers).json()
    raqamlar = {item["partiya_raqami"] for item in javob["items"]}
    assert raqamlar == {60301}


def test_qidiruv_xaridor_boyicha(client, db, admin_headers, mahsulot_tola):
    _partiya_yarat(db, mahsulot_tola.id, 604, holati=PartiyaHolati.sotilgan, xaridor="Aloqachi MChJ")
    _partiya_yarat(db, mahsulot_tola.id, 605, holati=PartiyaHolati.sotilgan, xaridor="Boshqa xaridor")

    javob = client.get("/api/v1/partiyalar", params={"qidiruv": "Aloqachi"}, headers=admin_headers).json()
    raqamlar = {item["partiya_raqami"] for item in javob["items"]}
    assert raqamlar == {604}


def test_qidiruv_bosh_qator_hech_narsani_filtrlamaydi(client, db, admin_headers, mahsulot_tola):
    _partiya_yarat(db, mahsulot_tola.id, 606)

    javob = client.get("/api/v1/partiyalar", params={"qidiruv": "   "}, headers=admin_headers).json()
    raqamlar = {item["partiya_raqami"] for item in javob["items"]}
    assert 606 in raqamlar

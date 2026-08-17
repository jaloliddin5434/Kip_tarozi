from datetime import date

from app.models.partiya import Partiya, PartiyaHolati


def test_parol_ornatilmagan_bolsa_kirish_rad_etiladi(client, admin_headers):
    javob = client.post("/api/v1/moliyaviy/kirish", json={"parol": "har-narsa"}, headers=admin_headers)
    assert javob.status_code == 400


def test_moliyaviy_kirish_va_himoyalangan_endpoint(client, admin_headers):
    ornatish = client.post("/api/v1/moliyaviy/parolni-ornatish", json={"parol": "maxfiy1234"}, headers=admin_headers)
    assert ornatish.status_code == 200

    # Oddiy admin tokeni bilan moliyaviy endpointga kirib bo'lmaydi
    rad = client.get("/api/v1/moliyaviy/uzex-narxlar", headers=admin_headers)
    assert rad.status_code == 401

    # Noto'g'ri moliyaviy parol
    notogri = client.post("/api/v1/moliyaviy/kirish", json={"parol": "notogri"}, headers=admin_headers)
    assert notogri.status_code == 401

    # To'g'ri parol — moliyaviy token olinadi
    kirish = client.post("/api/v1/moliyaviy/kirish", json={"parol": "maxfiy1234"}, headers=admin_headers)
    assert kirish.status_code == 200
    moliyaviy_token = kirish.json()["access_token"]
    moliyaviy_headers = {"Authorization": f"Bearer {moliyaviy_token}"}

    narxlar = client.get("/api/v1/moliyaviy/uzex-narxlar", headers=moliyaviy_headers)
    assert narxlar.status_code == 200
    assert len(narxlar.json()) == 4


def test_hisobot_sotilgan_partiyani_hisoblaydi(client, db, admin_headers, mahsulot_tola):
    client.post("/api/v1/moliyaviy/parolni-ornatish", json={"parol": "maxfiy1234"}, headers=admin_headers)
    moliyaviy_token = client.post(
        "/api/v1/moliyaviy/kirish", json={"parol": "maxfiy1234"}, headers=admin_headers
    ).json()["access_token"]
    moliyaviy_headers = {"Authorization": f"Bearer {moliyaviy_token}"}

    partiya = Partiya(
        mahsulot_id=mahsulot_tola.id,
        partiya_raqami=100,
        holati=PartiyaHolati.sotilgan,
        sotuv_sanasi=date.today(),
        xaridor="Test MChJ",
        sof_vazn=500.0,
        sotuv_narxi=9_250_000.0,
    )
    db.add(partiya)
    db.commit()

    hisobot = client.get("/api/v1/moliyaviy/hisobot", params={"davr": "oylik"}, headers=moliyaviy_headers)
    assert hisobot.status_code == 200
    tana = hisobot.json()
    assert tana["jami_summa"] == 9_250_000.0
    assert tana["mahsulotlar"][0]["mahsulot_kodi"] == "tola"
    assert tana["mahsulotlar"][0]["jami_sof_vazn"] == 500.0

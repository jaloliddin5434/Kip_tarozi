from app.core.security import parolni_hash, token_yarat
from app.models.foydalanuvchi import Foydalanuvchi, Rol


def _tayyor_mahsulotlar_headers(db) -> dict:
    foydalanuvchi = Foydalanuvchi(
        ism="Tayyor Mahsulot",
        login="tayyor_mahsulotlar_test",
        parol_hash=parolni_hash("parol123"),
        rol=Rol.tayyor_mahsulotlar,
    )
    db.add(foydalanuvchi)
    db.commit()
    db.refresh(foydalanuvchi)
    token = token_yarat(
        {"sub": str(foydalanuvchi.id), "rol": foydalanuvchi.rol.value, "smena": None, "tv": foydalanuvchi.token_versiyasi}
    )
    return {"Authorization": f"Bearer {token}"}


def _yopiq_partiya(client, operator_headers, partiya_raqami: int) -> dict:
    partiya = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": partiya_raqami}, headers=operator_headers
    ).json()
    client.patch(f"/api/v1/partiyalar/{partiya['id']}/yopish", headers=operator_headers)
    return partiya


def test_tayyor_mahsulotlar_sort_ogirlik_toldiradi(client, db, operator_headers, mahsulot_tola):
    partiya = _yopiq_partiya(client, operator_headers, 300)
    tm_headers = _tayyor_mahsulotlar_headers(db)

    javob = client.patch(
        f"/api/v1/partiyalar/{partiya['id']}/olchov-toldirish",
        json={"sort": "1-sort", "urama_bilan_vazn": 250.0, "urama_vazni": 5.0, "sof_vazn": 245.0, "kondicion_vazni": 240.0},
        headers=tm_headers,
    )
    assert javob.status_code == 200
    tana = javob.json()
    assert tana["sort"] == "1-sort"
    assert tana["urama_bilan_vazn"] == 250.0
    assert tana["sof_vazn"] == 245.0
    assert tana["holati"] == "yopiq"  # savdo hali yakunlanmagan
    assert tana["xaridor"] is None
    assert tana["sotuv_narxi"] is None
    assert tana["nakladnoy_raqami"] is None


def test_tayyor_mahsulotlar_xaridor_narx_etiborsiz_qoldiriladi(client, db, operator_headers, mahsulot_tola):
    partiya = _yopiq_partiya(client, operator_headers, 301)
    tm_headers = _tayyor_mahsulotlar_headers(db)

    javob = client.patch(
        f"/api/v1/partiyalar/{partiya['id']}/olchov-toldirish",
        json={
            "sort": "2-sort",
            "urama_bilan_vazn": 100.0,
            "urama_vazni": 3.0,
            "sof_vazn": 97.0,
            "xaridor": "Yashirin MChJ",
            "sotuv_narxi": 999_999.0,
            "dogovor_raqami": "D-1",
        },
        headers=tm_headers,
    )
    assert javob.status_code == 200
    tana = javob.json()
    assert tana["sort"] == "2-sort"
    # Sxemada bu maydonlar yo'q — jo'natilsa ham e'tiborsiz qoldiriladi
    assert tana["xaridor"] is None
    assert tana["sotuv_narxi"] is None
    assert tana["dogovor_raqami"] is None


def test_tayyor_mahsulotlar_sotish_endpointiga_kira_olmaydi(client, db, operator_headers, mahsulot_tola):
    partiya = _yopiq_partiya(client, operator_headers, 302)
    tm_headers = _tayyor_mahsulotlar_headers(db)

    javob = client.post(
        f"/api/v1/partiyalar/{partiya['id']}/sotish",
        json={
            "sotuv_sanasi": "2026-08-17",
            "xaridor": "Yashirin MChJ",
            "urama_bilan_vazn": 100.0,
            "urama_vazni": 3.0,
            "sof_vazn": 97.0,
        },
        headers=tm_headers,
    )
    assert javob.status_code == 403


def test_admin_olchov_toldirishga_ham_kiraoladi(client, db, operator_headers, admin_headers, mahsulot_tola):
    partiya = _yopiq_partiya(client, operator_headers, 303)

    javob = client.patch(
        f"/api/v1/partiyalar/{partiya['id']}/olchov-toldirish",
        json={"sort": "3-sort", "urama_bilan_vazn": 50.0, "urama_vazni": 1.0, "sof_vazn": 49.0},
        headers=admin_headers,
    )
    assert javob.status_code == 200
    assert javob.json()["sort"] == "3-sort"


def test_ochiq_partiyaga_olchov_toldirib_bolmaydi(client, operator_headers, db, mahsulot_tola):
    partiya = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": 304}, headers=operator_headers
    ).json()
    tm_headers = _tayyor_mahsulotlar_headers(db)

    javob = client.patch(
        f"/api/v1/partiyalar/{partiya['id']}/olchov-toldirish",
        json={"urama_bilan_vazn": 10.0, "urama_vazni": 1.0, "sof_vazn": 9.0},
        headers=tm_headers,
    )
    assert javob.status_code == 400

from app.core.security import parolni_hash
from app.models.audit_log import AuditLog
from app.models.foydalanuvchi import Foydalanuvchi, Rol


def _tayyor_foydalanuvchi(db) -> Foydalanuvchi:
    f = Foydalanuvchi(
        ism="Ombor Xodimi", login="ombor", parol_hash=parolni_hash("omborP"), rol=Rol.tayyor_mahsulotlar
    )
    db.add(f)
    db.commit()
    db.refresh(f)
    return f


def test_royxat_admin_barcha_hisoblarni_koradi(client, db, admin, admin_headers, operator):
    _tayyor_foydalanuvchi(db)

    javob = client.get("/api/v1/foydalanuvchilar", headers=admin_headers)
    assert javob.status_code == 200
    tana = javob.json()
    loginlar = {r["login"] for r in tana}
    assert {"test_admin", "smena_a", "ombor"}.issubset(loginlar)

    operator_qatori = next(r for r in tana if r["login"] == "smena_a")
    assert operator_qatori["rol"] == "operator"
    assert operator_qatori["smena"] == "A"


def test_royxat_faqat_admin(client, operator_headers):
    assert client.get("/api/v1/foydalanuvchilar", headers=operator_headers).status_code == 403
    assert client.get("/api/v1/foydalanuvchilar").status_code == 401


def test_login_ozgartirish_yangi_login_bilan_kirish(client, db, admin_headers, operator):
    javob = client.patch(
        f"/api/v1/foydalanuvchilar/{operator.id}", json={"login": "smena_a_yangi"}, headers=admin_headers
    )
    assert javob.status_code == 200
    assert javob.json()["login"] == "smena_a_yangi"

    # yangi login + eski parol bilan kirish ishlaydi
    kirish = client.post("/api/v1/auth/login", json={"login": "smena_a_yangi", "parol": "parolA"})
    assert kirish.status_code == 200
    # eski login endi ishlamaydi
    assert client.post("/api/v1/auth/login", json={"login": "smena_a", "parol": "parolA"}).status_code == 401


def test_parol_ozgartirish(client, db, admin_headers, operator):
    javob = client.patch(
        f"/api/v1/foydalanuvchilar/{operator.id}", json={"parol": "yangiParol123"}, headers=admin_headers
    )
    assert javob.status_code == 200

    assert client.post("/api/v1/auth/login", json={"login": "smena_a", "parol": "yangiParol123"}).status_code == 200
    assert client.post("/api/v1/auth/login", json={"login": "smena_a", "parol": "parolA"}).status_code == 401


def test_login_va_parol_birga(client, admin_headers, operator):
    javob = client.patch(
        f"/api/v1/foydalanuvchilar/{operator.id}",
        json={"login": "operator_x", "parol": "operatorX99"},
        headers=admin_headers,
    )
    assert javob.status_code == 200
    assert client.post("/api/v1/auth/login", json={"login": "operator_x", "parol": "operatorX99"}).status_code == 200


def test_login_band_bolsa_409(client, admin, admin_headers, operator):
    javob = client.patch(
        f"/api/v1/foydalanuvchilar/{operator.id}", json={"login": "test_admin"}, headers=admin_headers
    )
    assert javob.status_code == 409


def test_ozini_ozgartirish_mumkin(client, admin, admin_headers):
    javob = client.patch(
        f"/api/v1/foydalanuvchilar/{admin.id}", json={"parol": "yangiAdmin123"}, headers=admin_headers
    )
    assert javob.status_code == 200
    assert client.post("/api/v1/auth/login", json={"login": "test_admin", "parol": "yangiAdmin123"}).status_code == 200


def test_ikkalasi_ham_berilmasa_400(client, admin_headers, operator):
    javob = client.patch(f"/api/v1/foydalanuvchilar/{operator.id}", json={}, headers=admin_headers)
    assert javob.status_code == 400
    # bo'sh satrlar ham "berilmagan" deb hisoblanadi
    bosh = client.patch(
        f"/api/v1/foydalanuvchilar/{operator.id}", json={"login": "  ", "parol": ""}, headers=admin_headers
    )
    assert bosh.status_code == 400


def test_qisqa_parol_va_login_400(client, admin_headers, operator):
    assert client.patch(
        f"/api/v1/foydalanuvchilar/{operator.id}", json={"parol": "ab"}, headers=admin_headers
    ).status_code == 400
    assert client.patch(
        f"/api/v1/foydalanuvchilar/{operator.id}", json={"login": "ab"}, headers=admin_headers
    ).status_code == 400


def test_mavjud_bolmagan_id_404(client, admin_headers):
    assert client.patch(
        "/api/v1/foydalanuvchilar/999999", json={"parol": "parol123"}, headers=admin_headers
    ).status_code == 404


def test_patch_faqat_admin(client, operator_headers, operator):
    assert client.patch(
        f"/api/v1/foydalanuvchilar/{operator.id}", json={"parol": "parol123"}, headers=operator_headers
    ).status_code == 403


def test_audit_logga_yoziladi_lekin_parol_korinmaydi(client, db, admin, admin_headers, operator):
    javob = client.patch(
        f"/api/v1/foydalanuvchilar/{operator.id}",
        json={"login": "smena_a_2", "parol": "juda-maxfiy-parol"},
        headers=admin_headers,
    )
    assert javob.status_code == 200

    log = db.query(AuditLog).filter(
        AuditLog.jadval_nomi == "foydalanuvchilar", AuditLog.yozuv_id == operator.id
    ).one()
    assert log.foydalanuvchi_id == admin.id  # amalni bajargan admin
    assert log.amal.value == "tahrirlandi"
    assert log.yangi_qiymat["login"] == "smena_a_2"
    assert log.yangi_qiymat["parol"] == "o'zgartirildi"
    # haqiqiy parol hech qayerda yo'q
    butun_matn = f"{log.eski_qiymat} {log.yangi_qiymat} {log.sabab}"
    assert "juda-maxfiy-parol" not in butun_matn

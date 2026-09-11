"""Token bekor qilish mexanizmi (audit topilmasi tuzatishi): JWT ~10 yil
yashaydi, shuning uchun `foydalanuvchi.token_versiyasi` orqali eski
tokenlarni "hozirgacha yaroqli" ekanini tekshiramiz. Parol o'zgarganda yoki
admin alohida "tokenlarni bekor qilish" amalini bajarganda bu qiymat
oshadi — o'sha paytgacha yaratilgan BARCHA tokenlar (muddati tugamagan
bo'lsa ham) darhol 401 berishi kerak.
"""

from app.core.security import token_yarat


def _kirish(client, login: str, parol: str) -> str:
    javob = client.post("/api/v1/auth/login", json={"login": login, "parol": parol})
    assert javob.status_code == 200, javob.text
    return javob.json()["access_token"]


def _headers(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


# --- Asosiy oqim: login -> token ishlaydi ---


def test_yangi_token_ishlaydi(client, admin, admin_headers):
    javob = client.get("/api/v1/auth/men", headers=admin_headers)
    assert javob.status_code == 200
    assert javob.json()["id"] == admin.id


def test_login_orqali_olingan_token_ham_ishlaydi(client, admin):
    admin.parol_hash = admin.parol_hash  # (hech narsa o'zgartirmaydi — faqat aniqlik uchun)
    token = _kirish(client, admin.login, "parol123")
    javob = client.get("/api/v1/auth/men", headers=_headers(token))
    assert javob.status_code == 200


# --- "tv" claim yo'q (bu tuzatishdan OLDINGI eski token simulyatsiyasi) ---


def test_tv_claimisiz_eski_token_401(client, admin):
    eski_token = token_yarat({"sub": str(admin.id), "rol": admin.rol.value, "smena": None})  # "tv" YO'Q
    javob = client.get("/api/v1/auth/men", headers=_headers(eski_token))
    assert javob.status_code == 401


def test_notogri_tv_qiymatli_token_401(client, admin):
    yolgon_token = token_yarat({"sub": str(admin.id), "rol": admin.rol.value, "smena": None, "tv": 999})
    javob = client.get("/api/v1/auth/men", headers=_headers(yolgon_token))
    assert javob.status_code == 401


# --- Parol o'zgarganda: BARCHA eski tokenlar bekor bo'ladi ---


def test_parol_ozgarganda_eski_token_401_yangisi_ishlaydi(client, db, admin, admin_headers, operator, operator_headers):
    eski_token = operator_headers["Authorization"].removeprefix("Bearer ")
    assert client.get("/api/v1/auth/men", headers=operator_headers).status_code == 200
    eski_versiya = operator.token_versiyasi

    javob = client.patch(
        f"/api/v1/foydalanuvchilar/{operator.id}", json={"parol": "yangiParolA1"}, headers=admin_headers
    )
    assert javob.status_code == 200, javob.text

    db.refresh(operator)
    assert operator.token_versiyasi == eski_versiya + 1

    # Eski token endi ISHLAMAYDI
    javob = client.get("/api/v1/auth/men", headers=_headers(eski_token))
    assert javob.status_code == 401

    # Yangi parol bilan yangi login -> yangi token ISHLAYDI
    yangi_token = _kirish(client, operator.login, "yangiParolA1")
    javob = client.get("/api/v1/auth/men", headers=_headers(yangi_token))
    assert javob.status_code == 200
    assert javob.json()["id"] == operator.id

    # Eski parol endi ishlamaydi
    javob = client.post("/api/v1/auth/login", json={"login": operator.login, "parol": "parolA"})
    assert javob.status_code == 401


def test_login_ozgarsa_eski_token_ISHLASHDA_DAVOM_ETADI(client, db, admin, admin_headers, operator, operator_headers):
    """Faqat LOGIN o'zgarsa (parol emas) — token_versiyasi oshmaydi, eski
    token hali ham amal qiladi (kod: foydalanuvchilar.py izohi)."""
    javob = client.patch(
        f"/api/v1/foydalanuvchilar/{operator.id}", json={"login": "smena_a_yangi"}, headers=admin_headers
    )
    assert javob.status_code == 200, javob.text

    db.refresh(operator)
    javob = client.get("/api/v1/auth/men", headers=operator_headers)
    assert javob.status_code == 200


def test_audit_log_parol_ozgarganda_token_versiyasi_yozadi(client, db, admin, admin_headers, operator, operator_headers):
    from sqlalchemy import select

    from app.models.audit_log import AuditLog

    client.patch(f"/api/v1/foydalanuvchilar/{operator.id}", json={"parol": "yangiParolB2"}, headers=admin_headers)

    log = db.scalar(
        select(AuditLog)
        .where(AuditLog.jadval_nomi == "foydalanuvchilar", AuditLog.yozuv_id == operator.id)
        .order_by(AuditLog.id.desc())
    )
    assert log is not None
    assert log.yangi_qiymat["token_versiyasi"] == 2
    assert log.eski_qiymat["token_versiyasi"] == 1
    # Parolning O'ZI hech qachon log'ga tushmasligi shart bo'lib qoladi
    assert log.yangi_qiymat["parol"] == "o'zgartirildi"


# --- Admin "Tokenlarni bekor qilish" (parolsiz, favqulodda) ---


def test_tokenlarni_bekor_qilish_parolni_ozgartirmaydi(
    client, db, admin, admin_headers, operator, operator_headers
):
    eski_token = operator_headers["Authorization"].removeprefix("Bearer ")

    javob = client.post(f"/api/v1/foydalanuvchilar/{operator.id}/tokenlarni-bekor-qilish", headers=admin_headers)
    assert javob.status_code == 200, javob.text
    assert javob.json()["id"] == operator.id

    db.refresh(operator)
    assert operator.token_versiyasi == 2

    # Eski token endi ishlamaydi
    assert client.get("/api/v1/auth/men", headers=_headers(eski_token)).status_code == 401

    # Parol O'ZGARMAGAN — eski parol bilan hali ham login qilish mumkin
    yangi_token = _kirish(client, operator.login, "parolA")
    assert client.get("/api/v1/auth/men", headers=_headers(yangi_token)).status_code == 200


def test_tokenlarni_bekor_qilish_sababsiz_standart_matn_yoziladi(client, db, admin, admin_headers, operator):
    from sqlalchemy import select

    from app.models.audit_log import AuditLog

    client.post(f"/api/v1/foydalanuvchilar/{operator.id}/tokenlarni-bekor-qilish", headers=admin_headers)

    log = db.scalar(
        select(AuditLog)
        .where(AuditLog.jadval_nomi == "foydalanuvchilar", AuditLog.yozuv_id == operator.id)
        .order_by(AuditLog.id.desc())
    )
    assert log is not None
    assert "favqulodda" in log.sabab.lower()
    assert log.eski_qiymat == {"token_versiyasi": 1}
    assert log.yangi_qiymat == {"token_versiyasi": 2}


def test_tokenlarni_bekor_qilish_ozi_sabab_bersa_shu_yoziladi(client, db, admin, admin_headers, operator):
    from sqlalchemy import select

    from app.models.audit_log import AuditLog

    client.post(
        f"/api/v1/foydalanuvchilar/{operator.id}/tokenlarni-bekor-qilish",
        json={"sabab": "Operator kompyuteri o'g'irlandi"},
        headers=admin_headers,
    )

    log = db.scalar(
        select(AuditLog)
        .where(AuditLog.jadval_nomi == "foydalanuvchilar", AuditLog.yozuv_id == operator.id)
        .order_by(AuditLog.id.desc())
    )
    assert log.sabab == "Operator kompyuteri o'g'irlandi"


def test_tokenlarni_bekor_qilish_operator_kira_olmaydi(client, operator_headers, admin):
    javob = client.post(f"/api/v1/foydalanuvchilar/{admin.id}/tokenlarni-bekor-qilish", headers=operator_headers)
    assert javob.status_code == 403


def test_tokenlarni_bekor_qilish_tokensiz_401(client, admin):
    javob = client.post(f"/api/v1/foydalanuvchilar/{admin.id}/tokenlarni-bekor-qilish")
    assert javob.status_code == 401


def test_tokenlarni_bekor_qilish_mavjud_bolmagan_foydalanuvchi_404(client, admin_headers):
    javob = client.post("/api/v1/foydalanuvchilar/999999/tokenlarni-bekor-qilish", headers=admin_headers)
    assert javob.status_code == 404


def test_admin_ozini_bekor_qilishi_mumkin(client, db, admin, admin_headers):
    eski_token = admin_headers["Authorization"].removeprefix("Bearer ")

    javob = client.post(f"/api/v1/foydalanuvchilar/{admin.id}/tokenlarni-bekor-qilish", headers=admin_headers)
    assert javob.status_code == 200

    assert client.get("/api/v1/auth/men", headers=_headers(eski_token)).status_code == 401

    yangi_token = _kirish(client, admin.login, "parol123")
    assert client.get("/api/v1/auth/men", headers=_headers(yangi_token)).status_code == 200


def test_takroriy_bekor_qilish_versiyani_yana_oshiradi(client, db, admin, admin_headers, operator):
    client.post(f"/api/v1/foydalanuvchilar/{operator.id}/tokenlarni-bekor-qilish", headers=admin_headers)
    db.refresh(operator)
    assert operator.token_versiyasi == 2

    client.post(f"/api/v1/foydalanuvchilar/{operator.id}/tokenlarni-bekor-qilish", headers=admin_headers)
    db.refresh(operator)
    assert operator.token_versiyasi == 3

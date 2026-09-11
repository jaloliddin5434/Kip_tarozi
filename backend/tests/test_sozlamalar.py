"""`GET /sozlamalar` maxfiy qiymatlarni (Telegram bot tokenlari, moliyaviy
parol hash) API javobida maskalashi kerak — audit topilmasi tuzatishi.
Yozish (`PUT`) va backendning ichki o'qishi TO'LIQ qiymat bilan ishlashda
davom etadi, faqat tashqi HTTP javobi o'zgaradi.
"""

from app.models.sozlama import Sozlama


def _sozlama_yoz(db, kalit: str, qiymat: str) -> None:
    db.merge(Sozlama(kalit=kalit, qiymat=qiymat))
    db.commit()


def _royxatdan_top(javob: list[dict], kalit: str) -> dict:
    return next(q for q in javob if q["kalit"] == kalit)


# --- Ro'yxat (GET /sozlamalar) — maxfiy kalitlar maskalanadi ---


def test_royxat_telegram_tokenlar_maskalanadi(client, db, admin_headers):
    _sozlama_yoz(db, "telegram_xatolik_bot_token", "123456789:AAHXyzREALTOKENvalue1234")
    _sozlama_yoz(db, "telegram_statistika_bot_token", "987654321:BBHabcdefTOKENvalue5678")
    _sozlama_yoz(db, "telegram_surat_bot_token", "555555555:CCHtokenSuratBotiValue9012")
    # Chat ID — maxfiy EMAS, o'zgarishsiz qolishi kerak
    _sozlama_yoz(db, "telegram_xatolik_chat_id", "-1001234567890")

    javob = client.get("/api/v1/sozlamalar", headers=admin_headers)
    assert javob.status_code == 200
    natija = javob.json()

    xatolik = _royxatdan_top(natija, "telegram_xatolik_bot_token")
    assert xatolik["qiymat"] == "••••1234"
    assert "123456789" not in xatolik["qiymat"]
    assert "AAHXyz" not in xatolik["qiymat"]

    statistika = _royxatdan_top(natija, "telegram_statistika_bot_token")
    assert statistika["qiymat"] == "••••5678"

    surat = _royxatdan_top(natija, "telegram_surat_bot_token")
    assert surat["qiymat"] == "••••9012"

    chat_id = _royxatdan_top(natija, "telegram_xatolik_chat_id")
    assert chat_id["qiymat"] == "-1001234567890"


def test_royxat_moliyaviy_parol_hash_maskalanadi(client, db, admin_headers):
    _sozlama_yoz(db, "moliyaviy_parol_hash", "$2b$12$tasodifiyBcryptHashQiymatiXYZ7890")

    javob = client.get("/api/v1/sozlamalar", headers=admin_headers).json()
    qator = _royxatdan_top(javob, "moliyaviy_parol_hash")
    assert qator["qiymat"] == "••••7890"
    assert "$2b$12$" not in qator["qiymat"]


def test_royxat_boshqa_kalitlar_ozgarishsiz(client, db, admin_headers):
    _sozlama_yoz(db, "mavsum_boshlanish_sanasi", "2025-09-01")

    javob = client.get("/api/v1/sozlamalar", headers=admin_headers).json()
    qator = _royxatdan_top(javob, "mavsum_boshlanish_sanasi")
    assert qator["qiymat"] == "2025-09-01"


def test_royxat_qisqa_maxfiy_qiymat_tolik_yashiriladi(client, db, admin_headers):
    """4 belgidan qisqa/teng bo'lsa oxirgi belgilar ham ochilmasin — hamma
    narsa "••••" bilan almashadi (aks holda qisqa tokenning yarmi oshkor
    bo'lardi)."""
    _sozlama_yoz(db, "telegram_surat_bot_token", "abcd")

    javob = client.get("/api/v1/sozlamalar", headers=admin_headers).json()
    qator = _royxatdan_top(javob, "telegram_surat_bot_token")
    assert qator["qiymat"] == "••••"


def test_royxat_bosh_maxfiy_qiymat_bosh_qoladi(client, db, admin_headers):
    _sozlama_yoz(db, "telegram_xatolik_bot_token", "")

    javob = client.get("/api/v1/sozlamalar", headers=admin_headers).json()
    qator = _royxatdan_top(javob, "telegram_xatolik_bot_token")
    assert qator["qiymat"] == ""


# --- Bitta kalit (GET /sozlamalar/{kalit}) ---


def test_bitta_kalit_ham_maskalanadi(client, db, admin_headers):
    _sozlama_yoz(db, "telegram_statistika_bot_token", "111222333:realTokenQiymati4321")

    javob = client.get("/api/v1/sozlamalar/telegram_statistika_bot_token", headers=admin_headers)
    assert javob.status_code == 200
    assert javob.json()["qiymat"] == "••••4321"


def test_bitta_kalit_topilmasa_404(client, admin_headers):
    assert client.get("/api/v1/sozlamalar/mavjud_bolmagan_kalit", headers=admin_headers).status_code == 404


def test_operator_royxatga_kira_olmaydi(client, operator_headers):
    assert client.get("/api/v1/sozlamalar", headers=operator_headers).status_code == 403


# --- Yozish (PUT) — TO'LIQ qiymat bilan ishlashda davom etadi ---


def test_yozish_tolik_qiymatni_saqlaydi_javobda_maskalangan_qaytaradi(client, db, admin_headers):
    yangi_token = "999888777:YANGI_TOLIQ_TOKEN_qiymati0000"

    javob = client.put(
        "/api/v1/sozlamalar/telegram_xatolik_bot_token",
        json={"qiymat": yangi_token},
        headers=admin_headers,
    )
    assert javob.status_code == 200
    # PUT javobi ham maskalangan (ro'yxat/bitta-kalit bilan izchil)
    assert javob.json()["qiymat"] == "••••0000"

    # Bazada esa TO'LIQ qiymat saqlangan bo'lishi kerak
    db.expire_all()
    sozlama = db.get(Sozlama, "telegram_xatolik_bot_token")
    assert sozlama.qiymat == yangi_token


def test_yozgandan_keyin_royxatda_yangi_qiymat_maskasi_korinadi(client, db, admin_headers):
    client.put(
        "/api/v1/sozlamalar/telegram_surat_bot_token",
        json={"qiymat": "444555666:BoshqaYangiTokenQiymatABCD"},
        headers=admin_headers,
    )
    javob = client.get("/api/v1/sozlamalar", headers=admin_headers).json()
    qator = _royxatdan_top(javob, "telegram_surat_bot_token")
    assert qator["qiymat"] == "••••ABCD"


def test_backend_ozi_tolik_qiymatni_oqiydi(client, db, admin_headers, monkeypatch):
    """Maskalash FAQAT tashqi API javobiga tegishli — `telegram.py` xuddi
    avvalgidek to'liq (maskalanmagan) qiymatni o'qib, real so'rov yuborishi
    kerak."""
    import httpx as real_httpx

    from app.services import telegram

    yangi_token = "TOLIQ777888:HaqiqiyBackendIchidaOqiladiganQiymat"
    client.put(
        "/api/v1/sozlamalar/telegram_xatolik_bot_token",
        json={"qiymat": yangi_token},
        headers=admin_headers,
    )
    client.put(
        "/api/v1/sozlamalar/telegram_xatolik_chat_id",
        json={"qiymat": "-100777"},
        headers=admin_headers,
    )

    yuborilgan_url = {}

    def soxta_post(url, **kwargs):
        yuborilgan_url["url"] = url
        return real_httpx.Response(200, json={"ok": True}, request=real_httpx.Request("POST", url))

    monkeypatch.setattr(telegram.httpx, "post", soxta_post)
    telegram.xatolik_xabari(db, "sinov xabari")

    # URL ichida bot TO'LIQ tokeni bo'lishi kerak (maskalangan emas)
    assert yangi_token in yuborilgan_url["url"]
    assert "••••" not in yuborilgan_url["url"]

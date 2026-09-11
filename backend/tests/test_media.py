"""`app/api/v1/routes/media.py` — /media endpointlari AUTENTIFIKATSIYA bilan
himoyalanganini tekshiradi (audit tuzatishi: ilgari `StaticFiles` orqali
hech qanday tekshiruvsiz ochiq edi).
"""

import uuid
from datetime import datetime, timezone

from app.core.config import settings
from app.core.security import parolni_hash
from app.models.foydalanuvchi import Foydalanuvchi, Rol, Smena


def _tayyor_mahsulotlar_headers(client, db) -> dict:
    foydalanuvchi = Foydalanuvchi(
        ism="Tayyor Mahsulot",
        login="tayyor_mahsulotlar_media",
        parol_hash=parolni_hash("parol123"),
        rol=Rol.tayyor_mahsulotlar,
    )
    db.add(foydalanuvchi)
    db.commit()
    javob = client.post("/api/v1/auth/login", json={"login": foydalanuvchi.login, "parol": "parol123"})
    token = javob.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def _kip_yarat(client, headers, partiya_id: int, ogirlik: float = 120.0, surat_yoli: str | None = None) -> dict:
    tana = {
        "mijoz_id": str(uuid.uuid4()),
        "partiya_id": partiya_id,
        "ogirlik": ogirlik,
        "mahalliy_vaqt": datetime.now(timezone.utc).isoformat(),
    }
    if surat_yoli is not None:
        tana["surat_yoli"] = surat_yoli
    return client.post("/api/v1/kiplar", json=tana, headers=headers).json()


# --- nakladnoy: rol tekshiruvi ---


def test_nakladnoy_tokensiz_401(client, tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "STORAGE_PATH", str(tmp_path))
    javob = client.get("/media/nakladnoy/NK-000001.pdf")
    assert javob.status_code == 401


def test_nakladnoy_operator_403(client, operator_headers, tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "STORAGE_PATH", str(tmp_path))
    javob = client.get("/media/nakladnoy/NK-000001.pdf", headers=operator_headers)
    assert javob.status_code == 403


def test_nakladnoy_admin_fayl_topilmasa_404(client, admin_headers, tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "STORAGE_PATH", str(tmp_path))
    javob = client.get("/media/nakladnoy/yoq.pdf", headers=admin_headers)
    assert javob.status_code == 404


def test_nakladnoy_admin_haqiqiy_fayl_200(client, admin_headers, tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "STORAGE_PATH", str(tmp_path))
    papka = tmp_path / "nakladnoy"
    papka.mkdir()
    (papka / "NK-000123.pdf").write_bytes(b"%PDF-1.4 sinov")

    javob = client.get("/media/nakladnoy/NK-000123.pdf", headers=admin_headers)
    assert javob.status_code == 200
    assert javob.content == b"%PDF-1.4 sinov"
    assert javob.headers["content-type"] == "application/pdf"


def test_nakladnoy_tayyor_mahsulotlar_ham_kira_oladi(client, db, tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "STORAGE_PATH", str(tmp_path))
    papka = tmp_path / "nakladnoy"
    papka.mkdir()
    (papka / "NK-000124.pdf").write_bytes(b"%PDF-1.4")
    tm_headers = _tayyor_mahsulotlar_headers(client, db)

    javob = client.get("/media/nakladnoy/NK-000124.pdf", headers=tm_headers)
    assert javob.status_code == 200


def test_nakladnoy_fayl_nomida_slash_rad_etiladi(client, admin_headers, tmp_path, monkeypatch):
    """`/` yoki `\\` bo'lgan fayl nomi — yo'l ajratkichi sifatida ishlatilmasin
    (masalan boshqa papkaga chiqishga urinish)."""
    monkeypatch.setattr(settings, "STORAGE_PATH", str(tmp_path))
    (tmp_path / ".env").write_text("SECRET=xxx")

    javob = client.get("/media/nakladnoy/..%2F.env", headers=admin_headers)
    assert javob.status_code == 404
    assert b"SECRET" not in javob.content


def test_nakladnoy_path_traversal_rad_etiladi(client, admin_headers, tmp_path, monkeypatch):
    """`_xavfsiz_fayl` — natija STORAGE_PATH tashqarisiga chiqsa 404."""
    monkeypatch.setattr(settings, "STORAGE_PATH", str(tmp_path))
    tashqi = tmp_path.parent / "maxfiy_tashqi.txt"
    tashqi.write_text("tashqi maxfiy")

    javob = client.get(f"/media/nakladnoy/..%2F{tashqi.name}", headers=admin_headers)
    assert javob.status_code == 404
    assert b"maxfiy" not in javob.content


# --- kip-surat: istalgan autentifikatsiyalangan foydalanuvchi + smena qoidasi ---


def test_kip_surat_tokensiz_401(client, tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "STORAGE_PATH", str(tmp_path))
    javob = client.get("/media/kip-surat/2026-09/2026-09-10/Smena_A/Tola/x.jpg")
    assert javob.status_code == 401


def test_kip_surat_fayl_yoq_404(client, admin_headers, tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "STORAGE_PATH", str(tmp_path))
    javob = client.get("/media/kip-surat/2026-09/2026-09-10/Smena_A/Tola/yoq.jpg", headers=admin_headers)
    assert javob.status_code == 404


def test_kip_surat_admin_har_qanday_smenani_koradi(
    client, db, operator, operator_headers, admin_headers, mahsulot_tola, tmp_path, monkeypatch
):
    monkeypatch.setattr(settings, "STORAGE_PATH", str(tmp_path))
    nisbiy = "2026-09/2026-09-10/Smena_A/Tola/aaaa.jpg"
    papka = tmp_path / "2026-09" / "2026-09-10" / "Smena_A" / "Tola"
    papka.mkdir(parents=True)
    (papka / "aaaa.jpg").write_bytes(b"\xff\xd8\xff-jpeg-sinov")

    partiya = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": 900}, headers=operator_headers
    ).json()
    _kip_yarat(client, operator_headers, partiya["id"], surat_yoli=nisbiy)

    javob = client.get(f"/media/kip-surat/{nisbiy}", headers=admin_headers)
    assert javob.status_code == 200
    assert javob.content == b"\xff\xd8\xff-jpeg-sinov"
    assert javob.headers["content-type"] == "image/jpeg"


def test_kip_surat_operator_oz_smenasini_koradi(
    client, db, operator, operator_headers, mahsulot_tola, tmp_path, monkeypatch
):
    monkeypatch.setattr(settings, "STORAGE_PATH", str(tmp_path))
    nisbiy = "2026-09/2026-09-10/Smena_A/Tola/bbbb.jpg"
    papka = tmp_path / "2026-09" / "2026-09-10" / "Smena_A" / "Tola"
    papka.mkdir(parents=True)
    (papka / "bbbb.jpg").write_bytes(b"jpeg-a")

    partiya = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": 901}, headers=operator_headers
    ).json()
    _kip_yarat(client, operator_headers, partiya["id"], surat_yoli=nisbiy)

    javob = client.get(f"/media/kip-surat/{nisbiy}", headers=operator_headers)
    assert javob.status_code == 200


def test_kip_surat_operator_boshqa_smenani_korolmaydi(
    client, db, operator, operator_headers, mahsulot_tola, tmp_path, monkeypatch
):
    """`operator` fixture — Smena A. Boshqa smenadagi (B) operator hisobi
    yaratib, uning kipi suratini Smena A operatoridan yashiramiz."""
    monkeypatch.setattr(settings, "STORAGE_PATH", str(tmp_path))
    nisbiy = "2026-09/2026-09-10/Smena_B/Tola/cccc.jpg"
    papka = tmp_path / "2026-09" / "2026-09-10" / "Smena_B" / "Tola"
    papka.mkdir(parents=True)
    (papka / "cccc.jpg").write_bytes(b"jpeg-b")

    smena_b = Foydalanuvchi(
        ism="Smena B", login="smena_b_media", parol_hash=parolni_hash("parolB"), rol=Rol.operator, smena=Smena.B
    )
    db.add(smena_b)
    db.commit()
    b_token = client.post("/api/v1/auth/login", json={"login": "smena_b_media", "parol": "parolB"}).json()[
        "access_token"
    ]
    b_headers = {"Authorization": f"Bearer {b_token}"}

    partiya = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": 902}, headers=b_headers
    ).json()
    _kip_yarat(client, b_headers, partiya["id"], surat_yoli=nisbiy)

    # Smena A operatori (boshqa smena) — 403
    javob = client.get(f"/media/kip-surat/{nisbiy}", headers=operator_headers)
    assert javob.status_code == 403

    # Smena B operatorining o'zi — 200
    javob = client.get(f"/media/kip-surat/{nisbiy}", headers=b_headers)
    assert javob.status_code == 200


def test_kip_surat_path_traversal_rad_etiladi(client, admin_headers, tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "STORAGE_PATH", str(tmp_path))
    tashqi = tmp_path.parent / "maxfiy_kip_tashqi.txt"
    tashqi.write_text("maxfiy")

    javob = client.get(f"/media/kip-surat/..%2F{tashqi.name}", headers=admin_headers)
    assert javob.status_code == 404
    assert b"maxfiy" not in javob.content


def test_kip_surat_orfan_fayl_operatorga_berilmaydi(client, operator_headers, tmp_path, monkeypatch):
    """Hech qanday kip/shubhali holatga bog'lanmagan fayl (masalan eski/qo'lda
    joylashtirilgan) — operatorga berilmaydi (aniq egasi yo'q -> ruxsat yo'q),
    lekin admin ko'radi (yuqoridagi admin testida tasdiqlangan)."""
    monkeypatch.setattr(settings, "STORAGE_PATH", str(tmp_path))
    papka = tmp_path / "2026-09" / "2026-09-01" / "Smena_A" / "Tola"
    papka.mkdir(parents=True)
    (papka / "orfan.jpg").write_bytes(b"orfan")

    javob = client.get("/media/kip-surat/2026-09/2026-09-01/Smena_A/Tola/orfan.jpg", headers=operator_headers)
    assert javob.status_code == 403

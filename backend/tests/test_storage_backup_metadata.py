"""Sof-mantiq testlari — DB shart emas.

Zaxira nusxasidagi surat fayllariga tushunarli nom berish mantig'i
(scripts/storage_backup_metadata.py). Baza so'rovi mock qilinadi — bu yerda
faqat nom yasash / tozalash / xarita tuzish tekshiriladi.
"""

from decimal import Decimal

import pytest

from scripts.storage_backup_metadata import (
    nom_yasa,
    ogirlik_matni,
    xarita_yasa,
    xavfsiz_nom,
)


# --- xavfsiz_nom ---


@pytest.mark.parametrize(
    "kirish, kutilgan",
    [
        ("Tola", "Tola"),
        ("Tola / Lint", "Tola_Lint"),
        ('a<b>c:d"e/f\\g|h?i*j', "a_b_c_d_e_f_g_h_i_j"),
        ("  bo'sh joy  ", "bo'sh_joy"),
        ("...nuqta...", "nuqta"),
        ("___", "nomsiz"),
        ("", "nomsiz"),
        ("a\x00\x1fb", "a_b"),
    ],
)
def test_xavfsiz_nom(kirish, kutilgan):
    assert xavfsiz_nom(kirish) == kutilgan


# --- ogirlik_matni ---


@pytest.mark.parametrize(
    "kirish, kutilgan",
    [
        (Decimal("142.60"), "142.6"),
        (Decimal("142.00"), "142"),
        (Decimal("0.50"), "0.5"),
        (142.6, "142.6"),
        (130, "130"),
        ("204.70", "204.7"),
        (None, "0"),
        ("xato", "0"),
    ],
)
def test_ogirlik_matni(kirish, kutilgan):
    assert ogirlik_matni(kirish) == kutilgan


# --- nom_yasa ---


def test_nom_yasa_topshiriqdagi_misol():
    assert (
        nom_yasa("Tola", 55, 4, Decimal("142.60"))
        == "Tola_Partiya55_Kip4_142.6kg.jpg"
    )


def test_nom_yasa_kengaytma_saqlanadi():
    assert nom_yasa("Lint", 3, 12, Decimal("98.00"), ".jpeg").endswith("_98kg.jpeg")
    assert nom_yasa("Lint", 3, 12, Decimal("98.00"), "png").endswith("_98kg.png")


def test_nom_yasa_yaroqsiz_mahsulot_nomi_tozalanadi():
    nom = nom_yasa("Pu/x:*?", 1, 1, Decimal("100.00"))
    assert "/" not in nom and ":" not in nom and "*" not in nom and "?" not in nom
    assert nom == "Pu_x_Partiya1_Kip1_100kg.jpg"


def test_nom_yasa_raqamlar_butun_songa_keltiriladi():
    assert nom_yasa("Tola", "55", "4", Decimal("142.6")) == "Tola_Partiya55_Kip4_142.6kg.jpg"


# --- xarita_yasa ---


def test_xarita_yasa_asosiy():
    qatorlar = [
        ("2026-09/2026-09-09/Smena_A/Tola/d6d8e44f0a.jpg", "Tola", 55, 4, Decimal("142.60")),
        ("2026-09/2026-09-09/Smena_B/Lint/aabbccddee.jpg", "Lint", 3, 1, Decimal("98.00")),
    ]
    xarita = xarita_yasa(qatorlar)
    assert xarita == {
        "2026-09/2026-09-09/Smena_A/Tola/d6d8e44f0a.jpg": "Tola_Partiya55_Kip4_142.6kg.jpg",
        "2026-09/2026-09-09/Smena_B/Lint/aabbccddee.jpg": "Lint_Partiya3_Kip1_98kg.jpg",
    }


def test_xarita_yasa_surat_yoli_bosh_bolsa_tashlanadi():
    qatorlar = [
        (None, "Tola", 1, 1, Decimal("100.00")),
        ("", "Tola", 1, 2, Decimal("100.00")),
        ("2026-09/x/y/z/aaa.jpg", "Tola", 1, 3, Decimal("100.00")),
    ]
    xarita = xarita_yasa(qatorlar)
    assert list(xarita) == ["2026-09/x/y/z/aaa.jpg"]


def test_xarita_yasa_teskari_slash_va_boshdagi_slash_normallashadi():
    qatorlar = [("\\2026-09\\x\\y\\z\\aaa.jpg", "Tola", 1, 1, Decimal("50.00"))]
    xarita = xarita_yasa(qatorlar)
    assert list(xarita) == ["2026-09/x/y/z/aaa.jpg"]


def test_xarita_yasa_bir_xil_nom_raqam_bilan_farqlanadi():
    # Ikki xil fayl, lekin bir xil mahsulot/partiya/kip/ogirlik -> nom to'qnashadi
    qatorlar = [
        ("2026-09/a/b/c/fayl1.jpg", "Tola", 7, 2, Decimal("120.00")),
        ("2026-09/a/b/c/fayl2.jpg", "Tola", 7, 2, Decimal("120.00")),
        ("2026-09/a/b/c/fayl3.jpg", "Tola", 7, 2, Decimal("120.00")),
    ]
    xarita = xarita_yasa(qatorlar)
    nomlar = sorted(xarita.values())
    assert nomlar == [
        "Tola_Partiya7_Kip2_120kg.jpg",
        "Tola_Partiya7_Kip2_120kg_2.jpg",
        "Tola_Partiya7_Kip2_120kg_3.jpg",
    ]
    # Har bir manba fayl bitta noyob nomga tegishli
    assert len(set(xarita.values())) == 3


def test_xarita_yasa_bir_xil_surat_yoli_takrorlanmaydi():
    qatorlar = [
        ("2026-09/a/b/c/x.jpg", "Tola", 1, 1, Decimal("10.00")),
        ("2026-09/a/b/c/x.jpg", "Tola", 1, 1, Decimal("10.00")),
    ]
    xarita = xarita_yasa(qatorlar)
    assert xarita == {"2026-09/a/b/c/x.jpg": "Tola_Partiya1_Kip1_10kg.jpg"}


def test_xarita_yasa_shubhali_holat_surati_xaritaga_kirmaydi():
    # Bunday surat kiplar jadvalidan kelmaydi -> so'rov natijasida yo'q.
    # Ya'ni xaritada bo'lmaydi -> PowerShell asl nom bilan nusxalaydi.
    qatorlar = [("2026-09/a/b/Smena_A/Tola/real.jpg", "Tola", 1, 1, Decimal("10.00"))]
    xarita = xarita_yasa(qatorlar)
    assert "2026-09/a/b/Smena_A/shubhali_holatlar/shubha.jpg" not in xarita


# --- 0-QISM audit (4-band): _bazadan_qatorlar() haqiqatan real vaqtda ---
# --- bazadan o'qiganini (kesh yo'qligini) DB bilan tasdiqlaydi.        ---


def test_bazadan_qatorlar_kip_tahrirlangandan_keyin_yangi_holatni_korsatadi(
    db, client, operator, operator_headers, admin_headers, mahsulot_tola, monkeypatch, tmp_path
):
    """`_bazadan_qatorlar()` `app.core.database.SessionLocal` orqali HAR
    CHAQIRUVDA yangi ulanish ochadi — hech qanday kesh yo'q. Shu tufayli kip
    tahrirlanib (mahsulot o'zgarib) darhol keyingi chaqiruvda YANGI mahsulot
    nomi bilan chiqishi kerak."""
    import uuid
    from datetime import datetime, timezone

    from sqlalchemy.orm import sessionmaker

    from app.core.config import settings
    from app.models.mahsulot import Mahsulot
    from app.models.partiya import Partiya, PartiyaHolati
    from app.services.storage.rasm import rasm_saqla
    from scripts.storage_backup_metadata import _bazadan_qatorlar

    monkeypatch.setattr(settings, "STORAGE_PATH", str(tmp_path))

    # _bazadan_qatorlar() app.core.database.SessionLocal'ni chaqiradi (real
    # dev bazaga ulanadi) — testda buni shu testning izolyatsiyalangan
    # tranzaksiyasiga (db fixture) yo'naltiramiz, aks holda test ma'lumotlari
    # ko'rinmaydi.
    monkeypatch.setattr("app.core.database.SessionLocal", sessionmaker(bind=db.connection()))

    lint = Mahsulot(kod="lint_backup", nomi="Lint")
    db.add(lint)
    db.commit()
    db.refresh(lint)

    eski_partiya = Partiya(mahsulot_id=mahsulot_tola.id, partiya_raqami=800, holati=PartiyaHolati.ochiq)
    yangi_partiya = Partiya(mahsulot_id=lint.id, partiya_raqami=801, holati=PartiyaHolati.ochiq)
    db.add_all([eski_partiya, yangi_partiya])
    db.commit()
    db.refresh(eski_partiya)
    db.refresh(yangi_partiya)

    vaqt = datetime(2026, 9, 10, 10, 0, tzinfo=timezone.utc)
    nisbiy_yol = rasm_saqla(b"jpeg-sinov", smena="A", vaqt=vaqt, turi="kip", mahsulot_nomi="Tola")
    kip = client.post(
        "/api/v1/kiplar",
        json={
            "mijoz_id": str(uuid.uuid4()),
            "partiya_id": eski_partiya.id,
            "ogirlik": 42.0,
            "mahalliy_vaqt": datetime.now(timezone.utc).isoformat(),
            "surat_yoli": nisbiy_yol,
        },
        headers=operator_headers,
    ).json()

    qatorlar_oldin = _bazadan_qatorlar()
    qator_oldin = next(q for q in qatorlar_oldin if q[0] == nisbiy_yol)
    assert qator_oldin[1] == "Tola"  # (surat_yoli, mahsulot_nomi, partiya_raqami, kip_raqami, ogirlik)
    assert qator_oldin[2] == 800

    client.patch(
        f"/api/v1/kiplar/{kip['id']}",
        json={"mahsulot_kodi": "lint_backup", "partiya_raqami": 801, "sabab": "Noto'g'ri mahsulot tanlangan edi"},
        headers=admin_headers,
    )

    qatorlar_keyin = _bazadan_qatorlar()
    # surat_yoli ham Lint papkasiga ko'chgani uchun eski nisbiy_yol endi
    # bazada yo'q — YANGI (Lint) yo'l bilan qidiramiz.
    yangi_qator = next(q for q in qatorlar_keyin if q[2] == 801 and q[3] == qator_oldin[3])
    assert yangi_qator[1] == "Lint"
    assert "/Lint/" in yangi_qator[0]

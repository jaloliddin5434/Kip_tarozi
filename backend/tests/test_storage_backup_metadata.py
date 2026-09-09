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

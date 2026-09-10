"""Surat papka tuzilmasi testlari (rasm_saqla).

Yangi tuzilma:
    <Oy>/<Kun>/Smena_<A|B|C|D>/<Mahsulot nomi>/<fayl>.jpg      (turi="kip")
    <Oy>/<Kun>/Smena_<A|B|C|D>/shubhali_holatlar/<fayl>.jpg    (turi="shubha")
"""

from datetime import datetime, timezone

import pytest

from app.core.config import settings
from app.services.storage.rasm import rasm_kochir, rasm_saqla

BAYT = b"\xff\xd8\xff\xe0test\xff\xd9"
VAQT = datetime(2026, 9, 8, 14, 5, tzinfo=timezone.utc)


@pytest.fixture(autouse=True)
def _storage(monkeypatch, tmp_path):
    monkeypatch.setattr(settings, "STORAGE_PATH", str(tmp_path))
    return tmp_path


def test_kip_surati_oy_kun_smena_mahsulot_tartibida(_storage):
    yol = rasm_saqla(BAYT, smena="A", vaqt=VAQT, turi="kip", mahsulot_nomi="Tola")

    assert yol.startswith("2026-09/2026-09-08/Smena_A/Tola/")
    assert yol.endswith(".jpg")
    assert (_storage / yol).read_bytes() == BAYT


def test_kip_surati_mahsulot_nomi_berilmasa_umumiy(_storage):
    yol = rasm_saqla(BAYT, smena="B", vaqt=VAQT, turi="kip")
    assert yol.startswith("2026-09/2026-09-08/Smena_B/umumiy/")


def test_shubha_surati_mahsulot_papkasidan_tashqarida(_storage):
    yol = rasm_saqla(BAYT, smena="C", vaqt=VAQT, turi="shubha", mahsulot_nomi="Tola")

    assert yol.startswith("2026-09/2026-09-08/Smena_C/shubhali_holatlar/")
    assert "Tola" not in yol
    assert (_storage / yol).read_bytes() == BAYT


def test_har_bir_chaqiruv_yangi_fayl(_storage):
    a = rasm_saqla(BAYT, smena="A", vaqt=VAQT, turi="kip", mahsulot_nomi="Lint")
    b = rasm_saqla(BAYT, smena="A", vaqt=VAQT, turi="kip", mahsulot_nomi="Lint")
    assert a != b


# --- rasm_kochir (mahsulot tahrirlanganda surat ko'chirilishi) ---


def test_rasm_kochir_yangi_mahsulot_papkasiga_kochiradi(_storage):
    eski_yol = rasm_saqla(BAYT, smena="A", vaqt=VAQT, turi="kip", mahsulot_nomi="Tola")
    fayl_nomi = eski_yol.rsplit("/", 1)[-1]

    yangi_yol = rasm_kochir(eski_yol, smena="A", vaqt=VAQT, yangi_mahsulot_nomi="Lint")

    assert yangi_yol == f"2026-09/2026-09-08/Smena_A/Lint/{fayl_nomi}"
    assert not (_storage / eski_yol).exists()
    assert (_storage / yangi_yol).read_bytes() == BAYT


def test_rasm_kochir_fayl_nomi_ozgarmaydi(_storage):
    eski_yol = rasm_saqla(BAYT, smena="B", vaqt=VAQT, turi="kip", mahsulot_nomi="Pux")
    eski_fayl_nomi = eski_yol.rsplit("/", 1)[-1]

    yangi_yol = rasm_kochir(eski_yol, smena="B", vaqt=VAQT, yangi_mahsulot_nomi="Ulyuk")

    assert yangi_yol.rsplit("/", 1)[-1] == eski_fayl_nomi


def test_rasm_kochir_fayl_diskda_yoq_bolsa_eski_yolni_qaytaradi(_storage):
    natija = rasm_kochir(
        "2026-09/2026-09-08/Smena_A/Tola/yoq-fayl.jpg", smena="A", vaqt=VAQT, yangi_mahsulot_nomi="Lint"
    )
    assert natija == "2026-09/2026-09-08/Smena_A/Tola/yoq-fayl.jpg"

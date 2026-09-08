"""Surat papka tuzilmasi testlari (rasm_saqla).

Yangi tuzilma:
    <Oy>/<Kun>/Smena_<A|B|C|D>/<Mahsulot nomi>/<fayl>.jpg      (turi="kip")
    <Oy>/<Kun>/Smena_<A|B|C|D>/shubhali_holatlar/<fayl>.jpg    (turi="shubha")
"""

from datetime import datetime, timezone

import pytest

from app.core.config import settings
from app.services.storage.rasm import rasm_saqla

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

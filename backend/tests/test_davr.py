"""Sof-mantiq testlari — DB shart emas."""

from datetime import date

from app.services.davr import davr_oraligi, mavsum_boshlanishi


def test_kunlik():
    assert davr_oraligi("kunlik", date(2026, 8, 15)) == (date(2026, 8, 15), date(2026, 8, 15))


def test_haftalik_dushanbadan_yakshanbagacha():
    # 2026-08-15 — shanba
    boshlanish, tugash = davr_oraligi("haftalik", date(2026, 8, 15))
    assert boshlanish == date(2026, 8, 10)  # dushanba
    assert tugash == date(2026, 8, 16)  # yakshanba


def test_oylik_fevral_kabisa_bolmagan_yil():
    boshlanish, tugash = davr_oraligi("oylik", date(2026, 2, 10))
    assert boshlanish == date(2026, 2, 1)
    assert tugash == date(2026, 2, 28)


def test_mavsum_sentyabrdan_oldin():
    # Avgustda hali o'tgan yilgi mavsum davom etadi
    assert mavsum_boshlanishi(date(2026, 8, 31)) == date(2025, 9, 1)


def test_mavsum_sentyabrdan_keyin():
    assert mavsum_boshlanishi(date(2026, 9, 1)) == date(2026, 9, 1)
    assert mavsum_boshlanishi(date(2026, 12, 25)) == date(2026, 9, 1)


def test_noma_lum_davr_xato_beradi():
    import pytest

    with pytest.raises(ValueError):
        davr_oraligi("noma'lum", date(2026, 1, 1))

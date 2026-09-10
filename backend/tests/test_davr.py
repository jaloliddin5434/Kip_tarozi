"""davr_oraligi/mavsum_* testlari. Sof-mantiq testlari (DB shart emas) va
"mavsum" sozlamasiga bog'liq testlar (DB fixture kerak) aralash."""

from datetime import date

from app.models.sozlama import Sozlama
from app.services.davr import (
    davr_oraligi,
    mavsum_boshi,
    mavsum_boshi_sozlamadan,
    mavsum_boshlanishi,
)


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
    # Bu — faqat ZAXIRA (fallback) qoidani sinaydi (sozlama topilmaganda ishlatiladi)
    assert mavsum_boshlanishi(date(2026, 8, 31)) == date(2025, 9, 1)


def test_mavsum_sentyabrdan_keyin():
    assert mavsum_boshlanishi(date(2026, 9, 1)) == date(2026, 9, 1)
    assert mavsum_boshlanishi(date(2026, 12, 25)) == date(2026, 9, 1)


def test_mavsum_db_uzatilmasa_zaxira_qoida_ishlaydi():
    # db=None uzatilganda (masalan eski chaqiruvchi) — hali ham zaxira qoida ishlaydi
    assert mavsum_boshi(None, date(2026, 9, 9)) == date(2026, 9, 1)
    boshlanish, tugash = davr_oraligi("mavsum", date(2026, 9, 9))
    assert (boshlanish, tugash) == (date(2026, 9, 1), date(2026, 9, 9))


def test_noma_lum_davr_xato_beradi():
    import pytest

    with pytest.raises(ValueError):
        davr_oraligi("noma'lum", date(2026, 1, 1))


def test_mavsum_boshi_sozlama_mavjud_bolsa_undan_olinadi(db):
    db.add(Sozlama(kalit="mavsum_boshlanish_sanasi", qiymat="2025-09-01"))
    db.commit()

    assert mavsum_boshi_sozlamadan(db) == date(2025, 9, 1)
    # Sana 2026-09-09 bo'lsa ham (qattiq qoida 2026-09-01 der edi) — sozlama ustun turadi
    assert mavsum_boshi(db, date(2026, 9, 9)) == date(2025, 9, 1)

    boshlanish, tugash = davr_oraligi("mavsum", date(2026, 9, 9), db)
    assert boshlanish == date(2025, 9, 1)
    assert tugash == date(2026, 9, 9)


def test_mavsum_boshi_sozlama_ozgarsa_natija_ham_ozgaradi(db):
    db.add(Sozlama(kalit="mavsum_boshlanish_sanasi", qiymat="2024-09-01"))
    db.commit()
    assert mavsum_boshi(db, date(2026, 9, 9)) == date(2024, 9, 1)

    sozlama = db.get(Sozlama, "mavsum_boshlanish_sanasi")
    sozlama.qiymat = "2026-01-15"
    db.commit()
    assert mavsum_boshi(db, date(2026, 9, 9)) == date(2026, 1, 15)


def test_mavsum_boshi_sozlama_yoq_bolsa_zaxira_qoidaga_otadi(db):
    assert mavsum_boshi_sozlamadan(db) is None
    assert mavsum_boshi(db, date(2026, 9, 9)) == mavsum_boshlanishi(date(2026, 9, 9))
    assert mavsum_boshi(db, date(2026, 8, 31)) == mavsum_boshlanishi(date(2026, 8, 31))


def test_mavsum_boshi_sozlama_notogri_format_bolsa_zaxira_qoidaga_otadi(db):
    db.add(Sozlama(kalit="mavsum_boshlanish_sanasi", qiymat="notogri-sana"))
    db.commit()

    assert mavsum_boshi_sozlamadan(db) is None
    assert mavsum_boshi(db, date(2026, 9, 9)) == mavsum_boshlanishi(date(2026, 9, 9))


def test_mavsum_boshi_sozlama_bosh_qator_bolsa_zaxira_qoidaga_otadi(db):
    db.add(Sozlama(kalit="mavsum_boshlanish_sanasi", qiymat=""))
    db.commit()

    assert mavsum_boshi_sozlamadan(db) is None
    assert mavsum_boshi(db, date(2026, 9, 9)) == mavsum_boshlanishi(date(2026, 9, 9))

"""davr_oraligi/mavsum_* testlari. Sof-mantiq testlari (DB shart emas) va
"mavsum" sozlamasiga bog'liq testlar (DB fixture kerak) aralash."""

from datetime import date, datetime

from app.models.sozlama import Sozlama
from app.services.davr import (
    davr_oraligi,
    mavsum_boshi,
    mavsum_boshi_sozlamadan,
    mavsum_boshlanishi,
    sargable_oraliq,
    sargable_pastki,
    sargable_yuqori,
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


# --------------------------------------------------------------------------
# AUDIT TOPILMASI TUZATISHI — sargable_oraliq/pastki/yuqori: sof Python
# darajasidagi chegara arifmetikasi (kun boshi/oxiri, oy oxiri, yil oxiri).
# DB darajasidagi (vaqt zonasi bilan) ekvivalentlik testlari alohida fayl —
# tests/test_sargable_sana_filtri.py.
# --------------------------------------------------------------------------


def test_sargable_pastki_kun_boshi():
    assert sargable_pastki(date(2026, 9, 10)) == datetime(2026, 9, 10, 0, 0, 0)


def test_sargable_yuqori_ertasi_kun_boshi():
    # `sana`ning O'ZI emas, ERTASI kunning 00:00'i — `<` bilan solishtiriladi,
    # shunda `sana`ning butun 24 soati (23:59:59.999999gacha) qamrab olinadi.
    assert sargable_yuqori(date(2026, 9, 10)) == datetime(2026, 9, 11, 0, 0, 0)


def test_sargable_yuqori_naiv_datetime_tzinfo_yoq():
    # MUHIM: natija tzinfo'siz bo'lishi SHART (davr.py'dagi izohga qarang) —
    # aks holda DB sessiyasining TimeZone sozlamasidan mustaqil bo'lib qolib,
    # func.date() bilan mos kelmay qoladi.
    assert sargable_pastki(date(2026, 1, 1)).tzinfo is None
    assert sargable_yuqori(date(2026, 1, 1)).tzinfo is None


def test_sargable_yuqori_oy_oxiri_keyingi_oyga_otadi():
    # Fevral (kabisa bo'lmagan) oxiri — 28-fevral kiritilsa, yuqori chegara
    # 1-mart 00:00 bo'lishi kerak (29-fevral emas, chunki bunday sana yo'q).
    assert sargable_yuqori(date(2026, 2, 28)) == datetime(2026, 3, 1, 0, 0, 0)


def test_sargable_yuqori_yil_oxiri_keyingi_yilga_otadi():
    # 31-dekabr — yuqori chegara 1-yanvar (KEYINGI yil) 00:00 bo'lishi kerak.
    assert sargable_yuqori(date(2026, 12, 31)) == datetime(2027, 1, 1, 0, 0, 0)


def test_sargable_oraliq_bitta_kunlik_filtr():
    # "Kunlik" davr — boshlanish==tugash (bitta kun). Oraliq [D 00:00, D+1 00:00).
    pastki, yuqori = sargable_oraliq(date(2026, 9, 10), date(2026, 9, 10))
    assert pastki == datetime(2026, 9, 10, 0, 0, 0)
    assert yuqori == datetime(2026, 9, 11, 0, 0, 0)
    assert (yuqori - pastki).total_seconds() == 24 * 3600  # aniq bitta kun


def test_sargable_oraliq_oylik_davrni_qamrab_oladi():
    boshlanish, tugash = davr_oraligi("oylik", date(2026, 2, 10))
    pastki, yuqori = sargable_oraliq(boshlanish, tugash)
    assert pastki == datetime(2026, 2, 1, 0, 0, 0)
    assert yuqori == datetime(2026, 3, 1, 0, 0, 0)  # fevral 28 kun + 1


def test_sargable_oraliq_teng_boshlanish_yuqoriga_mos():
    # Ketma-ket ikkita kunlik so'rov (masalan 10-sentyabr va 11-sentyabr)
    # bir-birining ustiga chiqmasligi va orasida tirqish qolmasligi kerak —
    # birinchisining yuqori chegarasi ikkinchisining pastki chegarasiga TENG
    # bo'lishi kerak ('<' va '>=' operatorlar birgalikda aniq bo'linish beradi).
    _, yuqori_1 = sargable_oraliq(date(2026, 9, 10), date(2026, 9, 10))
    pastki_2, _ = sargable_oraliq(date(2026, 9, 11), date(2026, 9, 11))
    assert yuqori_1 == pastki_2

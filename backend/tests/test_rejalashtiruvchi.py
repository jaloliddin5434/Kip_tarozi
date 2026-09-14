"""Kunlik Telegram hisoboti (rejalashtiruvchi.py) — audit va yaxshilash.

AUDIT: hisobot HECH QACHON kelmagan sababi rejalashtiruvchi/advisory-lock
mantig'ida emas (test_advisory_lock.py buni alohida tasdiqlaydi) — sabab
operatsion (dev kompyuter kechqurun 20:00'da ishlamagan). Shu bilan birga
xabar VAQTI 08:30'ga va MAZMUNI "kechagi to'liq kun + mavsum jamlanmasi"ga
o'zgartirildi — shu ikkalasini quyidagi testlar tekshiradi.

Har bir qism ALOHIDA sinaladi: vaqt hisoblash (`kecha_sanasi`), kechagi kun
ma'lumotini olish (`_mahsulot_boyicha_qatorlar`), mavsum jamlanmasi
(`_jami_soni_va_ogirlik`), xabar matnini qurish (`_hisobot_matni`, DB
shart emas) va to'liq oqim (`_kunlik_hisobot_yubor`, real Telegramga
CHIQMAYDI — `statistika_xabari` monkeypatch qilinadi)."""

import uuid
from datetime import date, datetime, timedelta, timezone

from app.core.config import settings
from app.models.foydalanuvchi import Smena
from app.models.kip import Kip, KipHolati
from app.models.partiya import Partiya, PartiyaHolati
from app.models.sozlama import Sozlama
from app.services import rejalashtiruvchi


def _partiya_yarat(db, mahsulot_id, raqami):
    partiya = Partiya(mahsulot_id=mahsulot_id, partiya_raqami=raqami, holati=PartiyaHolati.ochiq)
    db.add(partiya)
    db.commit()
    db.refresh(partiya)
    return partiya


def _kip_yarat(db, partiya_id, kip_raqami, ogirlik, sana: date, operator_id):
    vaqt = datetime(sana.year, sana.month, sana.day, 10, 0, tzinfo=timezone.utc)
    kip = Kip(
        mijoz_id=str(uuid.uuid4()),
        partiya_id=partiya_id,
        kip_raqami=kip_raqami,
        ogirlik=ogirlik,
        smena=Smena.A,
        operator_id=operator_id,
        mahalliy_vaqt=vaqt,
        vaqt=vaqt,
        holati=KipHolati.aktiv,
    )
    db.add(kip)
    db.commit()
    return kip


# --- 0/6-QISM: standart hisobot vaqti endi ertalabki 08:30 ---


def test_hisobot_vaqti_standart_ertalab_08_30():
    assert settings.KUNLIK_HISOBOT_VAQTI == "08:30"


# --- 7-QISM: kecha_sanasi() — sof sana arifmetikasi (DB shart emas) ---


def test_kecha_sanasi_bugundan_bir_kun_oldin():
    assert rejalashtiruvchi.kecha_sanasi(date(2026, 9, 14)) == date(2026, 9, 13)


def test_kecha_sanasi_oy_boshida_oldingi_oyning_oxirgi_kuniga_otadi():
    assert rejalashtiruvchi.kecha_sanasi(date(2026, 9, 1)) == date(2026, 8, 31)


def test_kecha_sanasi_yil_boshida_oldingi_yilga_otadi():
    assert rejalashtiruvchi.kecha_sanasi(date(2026, 1, 1)) == date(2025, 12, 31)


def test_kecha_sanasi_argumentsiz_haqiqiy_bugundan_hisoblanadi():
    assert rejalashtiruvchi.kecha_sanasi() == date.today() - timedelta(days=1)


# --- 7-QISM: kechagi kun ma'lumotini olish — faqat SO'RALGAN kunni oladi ---


def test_mahsulot_boyicha_qatorlar_faqat_kechagi_kunni_oladi(db, operator, mahsulot_tola):
    partiya = _partiya_yarat(db, mahsulot_tola.id, 9001)
    kecha = date.today() - timedelta(days=1)
    bugun = date.today()
    _kip_yarat(db, partiya.id, 1, 100.0, kecha, operator.id)
    _kip_yarat(db, partiya.id, 2, 999.0, bugun, operator.id)  # bugungi kun hisoblanmasligi kerak

    qatorlar = rejalashtiruvchi._mahsulot_boyicha_qatorlar(db, kecha, kecha)

    assert len(qatorlar) == 1
    _nomi, soni, kg = qatorlar[0]
    assert soni == 1
    assert float(kg) == 100.0


def test_mahsulot_boyicha_qatorlar_bekor_qilingan_kip_hisoblanmaydi(db, operator, mahsulot_tola):
    partiya = _partiya_yarat(db, mahsulot_tola.id, 9002)
    kecha = date.today() - timedelta(days=1)
    kip = _kip_yarat(db, partiya.id, 1, 100.0, kecha, operator.id)
    kip.holati = KipHolati.bekor_qilingan
    db.commit()

    assert rejalashtiruvchi._mahsulot_boyicha_qatorlar(db, kecha, kecha) == []


def test_mahsulot_boyicha_qatorlar_malumot_yoq_bolsa_bosh_royxat(db):
    kecha = date.today() - timedelta(days=1)
    assert rejalashtiruvchi._mahsulot_boyicha_qatorlar(db, kecha, kecha) == []


# --- 8-QISM: mavsum jamlanmasi — guruhlamasdan JAMI son/og'irlik ---


def test_jami_soni_va_ogirlik_faqat_oraliq_ichidagilarni_qamraydi(db, operator, mahsulot_tola):
    partiya = _partiya_yarat(db, mahsulot_tola.id, 9003)
    mavsum_boshi = date.today() - timedelta(days=10)
    kecha = date.today() - timedelta(days=1)
    mavsumdan_oldin = date.today() - timedelta(days=20)

    _kip_yarat(db, partiya.id, 1, 100.0, mavsum_boshi, operator.id)
    _kip_yarat(db, partiya.id, 2, 50.0, kecha, operator.id)
    _kip_yarat(db, partiya.id, 3, 999.0, mavsumdan_oldin, operator.id)  # mavsumdan oldin — hisoblanmasin

    soni, kg = rejalashtiruvchi._jami_soni_va_ogirlik(db, mavsum_boshi, kecha)

    assert soni == 2
    assert kg == 150.0


def test_jami_soni_va_ogirlik_malumot_yoq_bolsa_nolga_teng(db):
    soni, kg = rejalashtiruvchi._jami_soni_va_ogirlik(db, date(2020, 1, 1), date(2020, 1, 1))
    assert soni == 0
    assert kg == 0.0


def test_jami_soni_va_ogirlik_bekor_qilingan_hisoblanmaydi(db, operator, mahsulot_tola):
    partiya = _partiya_yarat(db, mahsulot_tola.id, 9004)
    sana = date.today() - timedelta(days=1)
    kip = _kip_yarat(db, partiya.id, 1, 500.0, sana, operator.id)
    kip.holati = KipHolati.bekor_qilingan
    db.commit()

    soni, kg = rejalashtiruvchi._jami_soni_va_ogirlik(db, sana, sana)
    assert soni == 0
    assert kg == 0.0


# --- 7+8-QISM: xabar matnini qurish — sof mantiq, DB shart emas ---


def test_hisobot_matni_ikkala_bolim_ham_mavjud():
    matn = rejalashtiruvchi._hisobot_matni(
        kecha=date(2026, 9, 13),
        qatorlar=[("Tola", 3, 450.0)],
        mavsum_boshlanish=date(2025, 9, 1),
        mavsum_soni=120,
        mavsum_kg=45000.0,
    )

    assert "📅 Kecha (2026-09-13)" in matn
    assert "Tola: 3 ta, 450.0 kg" in matn
    assert "📊 Mavsum boshidan (2025-09-01 — 2026-09-13)" in matn
    assert "Jami: 120 ta, 45000.0 kg" in matn


def test_hisobot_matni_bir_nechta_mahsulot_qatorga_ajratiladi():
    matn = rejalashtiruvchi._hisobot_matni(
        kecha=date(2026, 9, 13),
        qatorlar=[("Tola", 2, 300.0), ("Lint", 1, 40.0)],
        mavsum_boshlanish=date(2025, 9, 1),
        mavsum_soni=3,
        mavsum_kg=340.0,
    )
    assert "Tola: 2 ta, 300.0 kg" in matn
    assert "Lint: 1 ta, 40.0 kg" in matn


def test_hisobot_matni_kecha_bosh_bolsa_maxsus_xabar_lekin_mavsum_bolimi_qoladi():
    matn = rejalashtiruvchi._hisobot_matni(
        kecha=date(2026, 9, 13),
        qatorlar=[],
        mavsum_boshlanish=date(2025, 9, 1),
        mavsum_soni=0,
        mavsum_kg=0.0,
    )

    assert "hech narsa tortilmadi" in matn
    assert "📊 Mavsum boshidan" in matn
    assert "Jami: 0 ta, 0.0 kg" in matn


# --- To'liq oqim: _kunlik_hisobot_yubor() — real Telegramga CHIQMAYDI ---


def test_kunlik_hisobot_yubor_togri_matn_bilan_yuboradi(db, monkeypatch, operator, mahsulot_tola):
    partiya = _partiya_yarat(db, mahsulot_tola.id, 9005)
    kecha = date.today() - timedelta(days=1)
    _kip_yarat(db, partiya.id, 1, 200.0, kecha, operator.id)

    mavsum_boshlanish = date.today() - timedelta(days=30)
    db.add(Sozlama(kalit="mavsum_boshlanish_sanasi", qiymat=mavsum_boshlanish.isoformat()))
    db.commit()

    yuborilgan = {}

    def _soxta_statistika_xabari(_db, matn):
        yuborilgan["matn"] = matn

    monkeypatch.setattr(rejalashtiruvchi, "statistika_xabari", _soxta_statistika_xabari)
    monkeypatch.setattr(rejalashtiruvchi, "SessionLocal", lambda: db)
    # `_kunlik_hisobot_yubor` ichida `finally: db.close()` chaqiriladi — bu
    # yerda `db` `client`/`db` fixture'ning UMUMIY sessiyasi, uni yopib
    # qo'ysak keyingi tozalash (fixture teardown) buzilishi mumkin edi.
    monkeypatch.setattr(db, "close", lambda: None)

    rejalashtiruvchi._kunlik_hisobot_yubor()

    assert "matn" in yuborilgan
    assert f"📅 Kecha ({kecha.isoformat()})" in yuborilgan["matn"]
    assert "200.0 kg" in yuborilgan["matn"]
    assert f"📊 Mavsum boshidan ({mavsum_boshlanish.isoformat()}" in yuborilgan["matn"]


def test_kunlik_hisobot_yubor_malumot_olishda_xato_bolsa_statistika_xabari_chaqirilmaydi(db, monkeypatch):
    chaqirildi = {"holat": False}

    def _soxta_statistika_xabari(_db, _matn):
        chaqirildi["holat"] = True

    def _xato_beruvchi_qatorlar(*_a, **_kw):
        raise RuntimeError("sinov xatosi")

    monkeypatch.setattr(rejalashtiruvchi, "statistika_xabari", _soxta_statistika_xabari)
    monkeypatch.setattr(rejalashtiruvchi, "SessionLocal", lambda: db)
    monkeypatch.setattr(db, "close", lambda: None)
    monkeypatch.setattr(rejalashtiruvchi, "_mahsulot_boyicha_qatorlar", _xato_beruvchi_qatorlar)

    rejalashtiruvchi._kunlik_hisobot_yubor()  # xato ko'tarilmasligi kerak (try/except ichida ushlanadi)

    assert chaqirildi["holat"] is False

"""Kunlik Telegram hisoboti (rejalashtiruvchi.py) — audit va yaxshilash.

AUDIT: hisobot HECH QACHON kelmagan sababi rejalashtiruvchi/advisory-lock
mantig'ida emas (test_advisory_lock.py buni alohida tasdiqlaydi) — sabab
operatsion (dev kompyuter kechqurun 20:00'da ishlamagan). Shu bilan birga
xabar VAQTI 08:30'ga va MAZMUNI "kechagi to'liq kun + mavsum jamlanmasi"ga
o'zgartirildi — shu ikkalasini quyidagi testlar tekshiradi.

Har bir qism ALOHIDA sinaladi: vaqt hisoblash (`kecha_sanasi`), kechagi kun
va mavsum ma'lumotini olish (`_mahsulot_boyicha_qatorlar` — IKKALASI HAM
shu bitta funksiya orqali, mahsulot bo'yicha guruhlab), xabar matnini
qurish (`_hisobot_matni`, DB shart emas) va to'liq oqim
(`_kunlik_hisobot_yubor`, real Telegramga CHIQMAYDI — `statistika_xabari`
monkeypatch qilinadi).

TUZATISH: "Mavsum boshidan" bo'limi ilgari faqat bitta jamlanma
"Jami: N ta, X kg" qatorini ko'rsatardi — endi "Kecha" bo'limidagi kabi
HAR BIR MAHSULOT uchun alohida qator beradi (oxirida ixtiyoriy umumiy
jamlanma bilan)."""

import uuid
from datetime import date, datetime, timedelta, timezone

from app.core.config import settings
from app.models.foydalanuvchi import Smena
from app.models.kip import Kip, KipHolati
from app.models.mahsulot import Mahsulot
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


# --- 8-QISM: mavsum bo'limi — endi HAM mahsulot bo'yicha guruhlangan ---
# (bir xil `_mahsulot_boyicha_qatorlar` funksiyasi, faqat oraliq boshqacha)


def test_mahsulot_boyicha_qatorlar_mavsum_oraligida_har_mahsulot_alohida(db, operator, mahsulot_tola):
    lint = Mahsulot(kod="lint", nomi="Lint")
    db.add(lint)
    db.commit()

    tola_partiya = _partiya_yarat(db, mahsulot_tola.id, 9003)
    lint_partiya = _partiya_yarat(db, lint.id, 9013)

    mavsum_boshi = date.today() - timedelta(days=10)
    kecha = date.today() - timedelta(days=1)
    mavsumdan_oldin = date.today() - timedelta(days=20)

    _kip_yarat(db, tola_partiya.id, 1, 100.0, mavsum_boshi, operator.id)
    _kip_yarat(db, tola_partiya.id, 2, 50.0, kecha, operator.id)
    _kip_yarat(db, lint_partiya.id, 1, 30.0, kecha, operator.id)
    _kip_yarat(db, tola_partiya.id, 3, 999.0, mavsumdan_oldin, operator.id)  # mavsumdan oldin — hisoblanmasin

    qatorlar = dict((nomi, (soni, float(kg))) for nomi, soni, kg in rejalashtiruvchi._mahsulot_boyicha_qatorlar(
        db, mavsum_boshi, kecha
    ))

    assert qatorlar["Tola"] == (2, 150.0)
    assert qatorlar["Lint"] == (1, 30.0)


def test_mahsulot_boyicha_qatorlar_mavsumda_malumot_yoq_bolsa_bosh_royxat(db):
    assert rejalashtiruvchi._mahsulot_boyicha_qatorlar(db, date(2020, 1, 1), date(2020, 1, 1)) == []


def test_mahsulot_boyicha_qatorlar_mavsumda_bekor_qilingan_hisoblanmaydi(db, operator, mahsulot_tola):
    partiya = _partiya_yarat(db, mahsulot_tola.id, 9004)
    sana = date.today() - timedelta(days=1)
    kip = _kip_yarat(db, partiya.id, 1, 500.0, sana, operator.id)
    kip.holati = KipHolati.bekor_qilingan
    db.commit()

    assert rejalashtiruvchi._mahsulot_boyicha_qatorlar(db, sana, sana) == []


# --- 7+8-QISM: xabar matnini qurish — sof mantiq, DB shart emas ---


def test_hisobot_matni_ikkala_bolim_ham_mahsulot_boyicha_ajratilgan():
    matn = rejalashtiruvchi._hisobot_matni(
        kecha=date(2026, 9, 13),
        kecha_qatorlari=[("Tola", 2, 411.1), ("Lint", 1, 213.8), ("Pux", 1, 214.5)],
        mavsum_boshlanish=date(2025, 9, 1),
        mavsum_qatorlari=[("Tola", 43, 9056.3), ("Lint", 15, 3200.5), ("Pux", 20, 4500.0)],
    )

    assert "📅 Kecha (2026-09-13)" in matn
    assert "Tola: 2 ta, 411.1 kg" in matn
    assert "Lint: 1 ta, 213.8 kg" in matn
    assert "Pux: 1 ta, 214.5 kg" in matn

    assert "📊 Mavsum boshidan (2025-09-01 — 2026-09-13)" in matn
    assert "Tola: 43 ta, 9056.3 kg" in matn
    assert "Lint: 15 ta, 3200.5 kg" in matn
    assert "Pux: 20 ta, 4500.0 kg" in matn
    # Ixtiyoriy umumiy jamlanma — mavsum bo'limi oxirida
    assert "(jami: 78 ta, 16756.8 kg)" in matn


def test_hisobot_matni_mavsum_qatorlari_kecha_bolimidan_MUSTAQIL():
    """Mavsum bo'limidagi mahsulotlar to'plami kechagi kundan farq qilishi
    mumkin (masalan kecha faqat Tola tortilgan bo'lsa-yu, mavsum davomida
    Lint ham bo'lgan) — ikkala bo'lim bir-biriga bog'liq emas."""
    matn = rejalashtiruvchi._hisobot_matni(
        kecha=date(2026, 9, 13),
        kecha_qatorlari=[("Tola", 2, 300.0)],
        mavsum_boshlanish=date(2025, 9, 1),
        mavsum_qatorlari=[("Tola", 40, 8000.0), ("Lint", 10, 2000.0)],
    )
    assert "Lint" not in matn.split("📊")[0]  # kecha bo'limida Lint yo'q
    assert "Lint: 10 ta, 2000.0 kg" in matn  # lekin mavsum bo'limida bor


def test_hisobot_matni_kecha_bosh_bolsa_maxsus_xabar_lekin_mavsum_bolimi_qoladi():
    matn = rejalashtiruvchi._hisobot_matni(
        kecha=date(2026, 9, 13),
        kecha_qatorlari=[],
        mavsum_boshlanish=date(2025, 9, 1),
        mavsum_qatorlari=[("Tola", 5, 500.0)],
    )

    assert "📅 Kecha (2026-09-13): hech narsa tortilmadi." in matn
    assert "📊 Mavsum boshidan" in matn
    assert "Tola: 5 ta, 500.0 kg" in matn


def test_hisobot_matni_mavsum_bosh_bolsa_ham_maxsus_xabar_beradi():
    matn = rejalashtiruvchi._hisobot_matni(
        kecha=date(2026, 9, 13),
        kecha_qatorlari=[("Tola", 1, 100.0)],
        mavsum_boshlanish=date(2025, 9, 1),
        mavsum_qatorlari=[],
    )
    assert "📊 Mavsum boshidan (2025-09-01 — 2026-09-13): hech narsa tortilmadi." in matn


# --- To'liq oqim: _kunlik_hisobot_yubor() — real Telegramga CHIQMAYDI ---


def test_kunlik_hisobot_yubor_togri_matn_bilan_yuboradi(db, monkeypatch, operator, mahsulot_tola):
    lint = Mahsulot(kod="lint", nomi="Lint")
    db.add(lint)
    db.commit()

    tola_partiya = _partiya_yarat(db, mahsulot_tola.id, 9005)
    lint_partiya = _partiya_yarat(db, lint.id, 9015)

    kecha = date.today() - timedelta(days=1)
    mavsum_boshlanish = date.today() - timedelta(days=30)
    ichkarida = date.today() - timedelta(days=15)

    _kip_yarat(db, tola_partiya.id, 1, 200.0, kecha, operator.id)  # kecha — faqat Tola
    _kip_yarat(db, lint_partiya.id, 1, 80.0, ichkarida, operator.id)  # mavsum ichida, lekin kecha emas

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

    matn = yuborilgan["matn"]
    kecha_bolimi, mavsum_bolimi = matn.split("📊")

    assert f"📅 Kecha ({kecha.isoformat()})" in kecha_bolimi
    assert "Tola: 1 ta, 200.0 kg" in kecha_bolimi
    assert "Lint" not in kecha_bolimi  # kecha faqat Tola tortilgan

    assert f"Mavsum boshidan ({mavsum_boshlanish.isoformat()}" in mavsum_bolimi
    assert "Tola: 1 ta, 200.0 kg" in mavsum_bolimi  # mavsum ichida — Tola ham bor
    assert "Lint: 1 ta, 80.0 kg" in mavsum_bolimi  # mavsum ichida — Lint HAM bor (kecha bo'limida yo'q edi)
    assert "(jami: 2 ta, 280.0 kg)" in mavsum_bolimi


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

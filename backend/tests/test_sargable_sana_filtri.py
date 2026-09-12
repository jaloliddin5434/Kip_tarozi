"""AUDIT TOPILMASI TUZATISHI: butun loyiha bo'ylab sana-oralig'i filtrlari
`func.date(ustun) >= X AND <= Y` (sargable EMAS — Postgres B-tree indeksni
ishlata olmaydi) o'rniga `ustun >= X_dt AND ustun < (Y+1kun)_dt` (SARGABLE)
ko'rinishiga o'tkazildi (`app/services/davr.py:sargable_oraliq/pastki/yuqori`).

Bu fayl ESKI (func.date) va YANGI (sargable) mantiqning REAL DB'da (haqiqiy
Postgres, DB sessiyasining joriy TimeZone sozlamasi bilan) ANIQ bir xil
natija berishini isbotlaydi — chegara holatlari (kun boshi/oxiri, oy oxiri,
yil oxiri) alohida-alohida tekshiriladi. Bu vazifaning eng nozik qismi —
vaqt zonasi: `Kip.vaqt` `timestamptz` (UTC'da saqlanadi), `func.date()`
uni DB sessiyasining TimeZone'i bo'yicha mahalliy sanaga aylantiradi;
`sargable_*()` esa ATAYLAB **naiv** (tzinfo'siz) datetime qaytaradi — bu
Postgres/psycopg2'ga XUDDI o'sha sessiya TimeZone orqali `timestamptz`ga
aylantirilishini majbur qiladi, natijada ikkala yo'l ANIQ bir xil chegarani
beradi (session TimeZone qanday sozlangan bo'lishidan qat'i nazar)."""

import uuid
from datetime import date, datetime, timedelta, timezone

from sqlalchemy import func, select

from app.models.kip import Kip, KipHolati
from app.models.partiya import Partiya, PartiyaHolati
from app.services.davr import sargable_oraliq, sargable_pastki, sargable_yuqori


def _partiya(db, mahsulot_id: int, raqami: int) -> Partiya:
    p = Partiya(mahsulot_id=mahsulot_id, partiya_raqami=raqami, holati=PartiyaHolati.ochiq)
    db.add(p)
    db.commit()
    db.refresh(p)
    return p


_keyingi_kip_raqami_hisoblagich = iter(range(1, 100_000))


def _kip_aniq_vaqtda(db, *, partiya_id: int, operator_id: int, smena, vaqt: datetime) -> Kip:
    """`vaqt` — UTC'da aniq belgilangan instant (server buni saqlaganidan
    keyin sessiya TimeZone'i bo'yicha "qaysi mahalliy kunga tushishi"
    tekshiriladi). `mahalliy_vaqt` ham xuddi shu qiymat bilan to'ldiriladi
    (bu ustun testda ahamiyatsiz, faqat NOT NULL talabi uchun). `kip_raqami`
    har chaqiruvda ketma-ket o'sadi (bitta partiya ichida unique bo'lishi
    kerak — `uq_kip_partiya_raqam`)."""
    k = Kip(
        mijoz_id=str(uuid.uuid4()),
        partiya_id=partiya_id,
        kip_raqami=next(_keyingi_kip_raqami_hisoblagich),
        ogirlik=100.0,
        smena=smena,
        operator_id=operator_id,
        mahalliy_vaqt=vaqt,
        vaqt=vaqt,
        holati=KipHolati.aktiv,
    )
    db.add(k)
    db.commit()
    db.refresh(k)
    return k


def _eski_id_toplami(db, sana_dan: date, sana_gacha: date) -> set[int]:
    """ESKI (sargable EMAS) mantiq — hozirgacha loyihada ishlatilgan shakl."""
    qatorlar = db.execute(
        select(Kip.id).where(func.date(Kip.vaqt) >= sana_dan, func.date(Kip.vaqt) <= sana_gacha)
    ).all()
    return {r[0] for r in qatorlar}


def _yangi_id_toplami(db, sana_dan: date, sana_gacha: date) -> set[int]:
    """YANGI (sargable) mantiq — shu vazifada joriy etilgan shakl."""
    pastki, yuqori = sargable_oraliq(sana_dan, sana_gacha)
    qatorlar = db.execute(select(Kip.id).where(Kip.vaqt >= pastki, Kip.vaqt < yuqori)).all()
    return {r[0] for r in qatorlar}


def test_kun_boshi_oxiri_chegara_instantlari_bir_xil_natija_beradi(db, operator, mahsulot_tola):
    """Real DB'da (joriy sessiya TimeZone'i bilan) — bir necha "xavfli"
    chegara instantini (kun boshidan bir mikrosekund oldin/keyin) qo'yib,
    ESKI va YANGI mantiq ANIQ bir xil ID to'plamini qaytarishini isbotlaydi."""
    from app.models.foydalanuvchi import Smena

    p = _partiya(db, mahsulot_tola.id, 9701)

    # Naiv (tzinfo'siz) instantlar — DB ularni sessiya TimeZone'i bo'yicha
    # timestamptz'ga aylantiradi, INSERT paytida ham (xuddi WHERE'dagi kabi).
    instantlar = {
        "9-sentabr oxiridan 1mks oldin": datetime(2026, 9, 9, 23, 59, 59, 999999),
        "10-sentabr aniq boshi": datetime(2026, 9, 10, 0, 0, 0, 0),
        "10-sentabr kun ichida (tush payti)": datetime(2026, 9, 10, 12, 0, 0),
        "10-sentabr oxiridan 1mks oldin": datetime(2026, 9, 10, 23, 59, 59, 999999),
        "11-sentabr aniq boshi": datetime(2026, 9, 11, 0, 0, 0, 0),
    }
    kip_idlar = {}
    for tavsif, vaqt in instantlar.items():
        kip = _kip_aniq_vaqtda(db, partiya_id=p.id, operator_id=operator.id, smena=Smena.A, vaqt=vaqt)
        kip_idlar[tavsif] = kip.id

    # Filtr: FAQAT 10-sentabr (bitta kunlik)
    eski = _eski_id_toplami(db, date(2026, 9, 10), date(2026, 9, 10))
    yangi = _yangi_id_toplami(db, date(2026, 9, 10), date(2026, 9, 10))

    assert eski == yangi, f"ESKI va YANGI mantiq FARQ QILDI! eski={eski} yangi={yangi}"

    # Aniq qaysi kiplar kirishi kerakligini ham tasdiqlaymiz (nazariy tahlil
    # bilan mos): faqat "10-sentabr"ga tegishli 3 tasi, chegaradan tashqari
    # ikkitasi (9-sentabr oxiri, 11-sentabr boshi) YO'Q.
    kutilgan = {
        kip_idlar["10-sentabr aniq boshi"],
        kip_idlar["10-sentabr kun ichida (tush payti)"],
        kip_idlar["10-sentabr oxiridan 1mks oldin"],
    }
    assert eski == kutilgan, f"Kutilmagan natija: {eski} != {kutilgan}"
    assert kip_idlar["9-sentabr oxiridan 1mks oldin"] not in eski
    assert kip_idlar["11-sentabr aniq boshi"] not in eski


def test_oy_oxiri_chegarasi_bir_xil_natija_beradi(db, operator, mahsulot_tola):
    """Fevral oxiri (28-fevral, kabisa yil emas) — "oylik" davr filtri
    (1-fevraldan 28-fevralgacha) chegarasida ESKI/YANGI mos kelishi."""
    from app.models.foydalanuvchi import Smena

    p = _partiya(db, mahsulot_tola.id, 9702)

    fevral_oxiri = _kip_aniq_vaqtda(
        db, partiya_id=p.id, operator_id=operator.id, smena=Smena.A,
        vaqt=datetime(2026, 2, 28, 23, 59, 59, 999999),
    )
    mart_boshi = _kip_aniq_vaqtda(
        db, partiya_id=p.id, operator_id=operator.id, smena=Smena.A,
        vaqt=datetime(2026, 3, 1, 0, 0, 0, 0),
    )

    eski = _eski_id_toplami(db, date(2026, 2, 1), date(2026, 2, 28))
    yangi = _yangi_id_toplami(db, date(2026, 2, 1), date(2026, 2, 28))

    assert eski == yangi
    assert fevral_oxiri.id in eski
    assert mart_boshi.id not in eski


def test_yil_oxiri_chegarasi_bir_xil_natija_beradi(db, operator, mahsulot_tola):
    """31-dekabr / 1-yanvar (keyingi YIL) chegarasi — kalendar yil chegarasi
    ham to'g'ri ishlashini tasdiqlaydi (oy emas, yil o'zgaradi)."""
    from app.models.foydalanuvchi import Smena

    p = _partiya(db, mahsulot_tola.id, 9703)

    yil_oxiri = _kip_aniq_vaqtda(
        db, partiya_id=p.id, operator_id=operator.id, smena=Smena.A,
        vaqt=datetime(2026, 12, 31, 23, 59, 59, 999999),
    )
    yangi_yil = _kip_aniq_vaqtda(
        db, partiya_id=p.id, operator_id=operator.id, smena=Smena.A,
        vaqt=datetime(2027, 1, 1, 0, 0, 0, 0),
    )

    eski = _eski_id_toplami(db, date(2026, 1, 1), date(2026, 12, 31))
    yangi = _yangi_id_toplami(db, date(2026, 1, 1), date(2026, 12, 31))

    assert eski == yangi
    assert yil_oxiri.id in eski
    assert yangi_yil.id not in eski


def test_bitta_kunlik_filtr_faqat_ozini_qamrab_oladi(db, operator, mahsulot_tola):
    """"Kunlik" davr (boshlanish==tugash) — faqat o'sha kun, qo'shni kunlar
    umuman kirmasligi kerak (ESKI va YANGI ikkalasida ham)."""
    from app.models.foydalanuvchi import Smena

    p = _partiya(db, mahsulot_tola.id, 9704)

    oldingi = _kip_aniq_vaqtda(db, partiya_id=p.id, operator_id=operator.id, smena=Smena.A, vaqt=datetime(2026, 5, 14, 23, 0, 0))
    joriy = _kip_aniq_vaqtda(db, partiya_id=p.id, operator_id=operator.id, smena=Smena.A, vaqt=datetime(2026, 5, 15, 10, 0, 0))
    keyingi = _kip_aniq_vaqtda(db, partiya_id=p.id, operator_id=operator.id, smena=Smena.A, vaqt=datetime(2026, 5, 16, 1, 0, 0))

    eski = _eski_id_toplami(db, date(2026, 5, 15), date(2026, 5, 15))
    yangi = _yangi_id_toplami(db, date(2026, 5, 15), date(2026, 5, 15))

    assert eski == yangi == {joriy.id}
    assert oldingi.id not in eski
    assert keyingi.id not in eski


def test_sargable_pastki_yuqori_mustaqil_filtrlar_bir_xil(db, operator, mahsulot_tola):
    """`hujjatlar.py`/`kamera_tasdiq.py`/`kip_togrilash.py`/`shubhali_holatlar.py`
    kabi IKKALASI HAM IXTIYORIY (faqat pastki, faqat yuqori, yoki ikkalasi)
    filtrlar uchun ishlatiladigan `sargable_pastki`/`sargable_yuqori`ni
    alohida-alohida (`sargable_oraliq` emas) ham tekshiramiz."""
    from app.models.foydalanuvchi import Smena

    p = _partiya(db, mahsulot_tola.id, 9705)
    kip = _kip_aniq_vaqtda(db, partiya_id=p.id, operator_id=operator.id, smena=Smena.A, vaqt=datetime(2026, 6, 10, 15, 0, 0))

    # Faqat pastki chegara (sana_dan)
    eski_pastki = db.execute(select(Kip.id).where(func.date(Kip.vaqt) >= date(2026, 6, 10))).all()
    yangi_pastki = db.execute(select(Kip.id).where(Kip.vaqt >= sargable_pastki(date(2026, 6, 10)))).all()
    assert {r[0] for r in eski_pastki} == {r[0] for r in yangi_pastki}
    assert kip.id in {r[0] for r in yangi_pastki}

    # Faqat yuqori chegara (sana_gacha)
    eski_yuqori = db.execute(select(Kip.id).where(func.date(Kip.vaqt) <= date(2026, 6, 10))).all()
    yangi_yuqori = db.execute(select(Kip.id).where(Kip.vaqt < sargable_yuqori(date(2026, 6, 10)))).all()
    assert {r[0] for r in eski_yuqori} == {r[0] for r in yangi_yuqori}
    assert kip.id in {r[0] for r in yangi_yuqori}


def test_utc_va_mahalliy_kun_farqli_bolgan_instant_ham_togri_ishlaydi(db, operator, mahsulot_tola):
    """Real DB sessiyasi UTC+5'da ishlaydi (audit topilmasi — server Toshkent
    vaqtida). Shu sabab UTC bo'yicha 19:00-23:59 oralig'idagi instant UTC
    kalendarida BIR kun, lekin mahalliy (+5) kalendarida ALLAQACHON KEYINGI
    kun bo'ladi. Bu aynan `func.date()`ning "session TimeZone bo'yicha"
    ishlashini isbotlaydigan holat — ESKI/YANGI shu yerda ham mos kelishi
    KERAK (ikkalasi ham bir xil sessiya TimeZone mexanizmidan foydalanadi)."""
    from app.models.foydalanuvchi import Smena

    p = _partiya(db, mahsulot_tola.id, 9706)

    # UTC 2026-09-10 20:00:00 -> sessiya +5 bo'lsa mahalliy 2026-09-11 01:00 (KEYINGI kun!)
    utc_instant = datetime(2026, 9, 10, 20, 0, 0, tzinfo=timezone.utc)
    kip = Kip(
        mijoz_id=str(uuid.uuid4()), partiya_id=p.id, kip_raqami=next(_keyingi_kip_raqami_hisoblagich),
        ogirlik=100.0, smena=Smena.A, operator_id=operator.id,
        mahalliy_vaqt=utc_instant, vaqt=utc_instant, holati=KipHolati.aktiv,
    )
    db.add(kip)
    db.commit()
    db.refresh(kip)

    # DB'dan haqiqiy mahalliy sanasini so'raymiz (session TimeZone qanday
    # bo'lishidan qat'i nazar, bu — "haqiqat manbai").
    mahalliy_sana = db.execute(select(func.date(Kip.vaqt)).where(Kip.id == kip.id)).scalar_one()
    if not isinstance(mahalliy_sana, date):
        mahalliy_sana = date.fromisoformat(str(mahalliy_sana))

    eski = _eski_id_toplami(db, mahalliy_sana, mahalliy_sana)
    yangi = _yangi_id_toplami(db, mahalliy_sana, mahalliy_sana)
    assert eski == yangi == {kip.id}

    # Va — agar kimdir NOTO'G'RI ravishda UTC kalendar sanasidan foydalansa
    # (bu funksiyaning maqsadi aynan shu xatoni oldini olish), natija boshqacha
    # bo'lardi — buni ham hujjatlashtirib qo'yamiz (session +5 bo'lganda).
    utc_sana = utc_instant.date()
    if utc_sana != mahalliy_sana:
        yangi_utc_sana_bilan = _yangi_id_toplami(db, utc_sana, utc_sana)
        assert kip.id not in yangi_utc_sana_bilan, (
            "Agar bu tasdiqlansa, demak UTC/mahalliy sana farqi shu muhitda "
            "kutilganidek namoyon bo'lmoqda"
        )

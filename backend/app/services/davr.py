import logging
from datetime import date, datetime, time, timedelta

from sqlalchemy.orm import Session

from app.models.sozlama import Sozlama

DavrTuri = str  # "kunlik" | "haftalik" | "oylik" | "mavsum"

logger = logging.getLogger("davr")

# Mavsum boshlanish sanasini shu sozlama kaliti belgilaydi (Sozlamalar ekrani).
# Barcha "mavsum" davriga bog'liq joylar (Statistika, Dashboard, Rekord,
# Moliyaviy, Mavsum jurnali) shu sozlamani o'qishi kerak — qattiq kodlangan
# 1-sentyabr qoidasi faqat sozlama topilmagandagi zaxira (fallback).
MAVSUM_BOSHI_SOZLAMA_KALITI = "mavsum_boshlanish_sanasi"


def mavsum_boshlanishi(sana: date) -> date:
    """Zaxira (fallback) qoida: sozlama topilmasa/noto'g'ri bo'lsa ishlatiladi —
    mavsum har yili 1-sentyabrdan boshlanadi deb hisoblanadi."""
    if sana.month >= 9:
        return date(sana.year, 9, 1)
    return date(sana.year - 1, 9, 1)


def mavsum_boshi_sozlamadan(db: Session) -> date | None:
    """`mavsum_boshlanish_sanasi` sozlamasini bazadan o'qiydi. Sozlama yo'q,
    bo'sh yoki noto'g'ri formatda bo'lsa — None qaytaradi (chaqiruvchi zaxira
    qoidaga o'tishi kerak)."""
    sozlama = db.get(Sozlama, MAVSUM_BOSHI_SOZLAMA_KALITI)
    if sozlama is None or not sozlama.qiymat:
        return None
    try:
        return date.fromisoformat(sozlama.qiymat.strip())
    except ValueError:
        logger.warning(
            "%s sozlamasi noto'g'ri formatda (%r) — zaxira 1-sentyabr qoidasi ishlatilmoqda",
            MAVSUM_BOSHI_SOZLAMA_KALITI,
            sozlama.qiymat,
        )
        return None


def mavsum_boshi(db: Session | None, sana: date) -> date:
    """Mavsum boshlanish sanasi — HAMISHA `mavsum_boshlanish_sanasi`
    sozlamasidan olinadi. Sozlama topilmasa (yoki db uzatilmagan bo'lsa) —
    zaxira sifatida eng so'nggi 1-sentyabr qoidasi ishlatiladi, va bu holat
    log orqali ogohlantiriladi."""
    if db is not None:
        sozlama_sanasi = mavsum_boshi_sozlamadan(db)
        if sozlama_sanasi is not None:
            return sozlama_sanasi
        logger.warning(
            "%s sozlamasi topilmadi/bo'sh — zaxira 1-sentyabr qoidasi ishlatilmoqda",
            MAVSUM_BOSHI_SOZLAMA_KALITI,
        )
    return mavsum_boshlanishi(sana)


def davr_oraligi(davr: DavrTuri, sana: date, db: Session | None = None) -> tuple[date, date]:
    if davr == "kunlik":
        return sana, sana

    if davr == "haftalik":
        boshlanish = sana - timedelta(days=sana.weekday())  # dushanba
        return boshlanish, boshlanish + timedelta(days=6)

    if davr == "oylik":
        boshlanish = sana.replace(day=1)
        keyingi_oy_boshi = (boshlanish.replace(day=28) + timedelta(days=4)).replace(day=1)
        return boshlanish, keyingi_oy_boshi - timedelta(days=1)

    if davr == "mavsum":
        return mavsum_boshi(db, sana), sana

    raise ValueError(f"Noma'lum davr turi: {davr}")


def sargable_oraliq(boshlanish: date, tugash: date) -> tuple[datetime, datetime]:
    """AUDIT TOPILMASI TUZATISHI: butun loyiha bo'ylab sana-oralig'i filtrlari
    `func.date(ustun) >= boshlanish AND func.date(ustun) <= tugash`
    ko'rinishida yozilgan edi — `date()` funksiyasi ustunga qo'llangani
    uchun PostgreSQL bu yerda B-tree indeksni ISHLATA OLMAYDI (funksional
    indeks ham `date(timestamptz)` IMMUTABLE emasligi sababli yaratib
    bo'lmaydi — qarang `app/models/kip.py`, migratsiya 68a051b132ed).

    Bu funksiya o'rniga SARGABLE (indeks ishlata oladigan) chegaralarni
    qaytaradi: `ustun >= pastki AND ustun < yuqori` (E'TIBOR: `tugash`dan
    KEYINGI kunning boshigacha, QAT'IY `<` bilan — shunda `tugash` sanasining
    O'ZI TO'LIQ (24 soatning oxirigacha) qamrab olinadi, lekin bitta ortiqcha
    kun QO'SHILMAYDI).

    MUHIM (vaqt zonasi): natija ATAYLAB **naiv** (tzinfo'siz) `datetime`
    obyektlari — bu ASOSIY xavfsizlik: agar bu yerda aniq UTC yoki boshqa
    tzinfo biriktirilsa, natija DB sessiyasining joriy `TimeZone`
    sozlamasidan (hozir server "Asia/Tashkent"ga yaqin, amalda
    "Asia/Yekaterinburg" — ikkalasi ham doim UTC+5, DST yo'q) MUSTAQIL bo'lib
    qolib, eski `func.date()` xatti-harakatidan farqlanib qolardi — chunki
    `func.date(timestamptz_ustun)`NING O'ZI ustunni (UTC'da saqlangan)
    sessiya TimeZone'i bo'yicha mahalliy sanaga aylantiradi. Naiv Python
    `datetime` psycopg2/SQLAlchemy orqali "timestamp without time zone"
    literali sifatida yuboriladi, Postgres esa uni `timestamptz` ustun bilan
    solishtirishda XUDDI o'sha sessiya TimeZone'i bo'yicha `timestamptz`ga
    aylantiradi — natijada `func.date()` bilan ANIQ bir xil chegara olinadi
    (real DB'da bir nechta chegara holati — kun boshi/oxiri instansiyalari —
    qo'lda tekshirilib tasdiqlangan, qarang PR/vazifa tavsifi)."""
    return sargable_pastki(boshlanish), sargable_yuqori(tugash)


def sargable_pastki(sana: date) -> datetime:
    """`sana`ning o'zidan (kun boshidan) boshlab qamrab oluvchi pastki
    chegara — `func.date(ustun) >= sana`ga teng. `sana_dan`/`sana_gacha`
    kabi IKKALASI HAM IXTIYORIY (bir-biridan mustaqil) filtrlar uchun,
    `sargable_oraliq()` ikkalasi ham berilishini talab qilgani uchun mos
    kelmaydigan joylarda ishlatiladi."""
    return datetime.combine(sana, time.min)


def sargable_yuqori(sana: date) -> datetime:
    """`sana`ning o'zini to'liq (kun oxirigacha) qamrab oluvchi, lekin
    ERTASI kundan QAT'IY OLDIN to'xtaydigan yuqori chegara (`<` bilan
    solishtiriladi) — `func.date(ustun) <= sana`ga teng."""
    return datetime.combine(sana + timedelta(days=1), time.min)

import logging
from datetime import date, timedelta

from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger
from sqlalchemy import func, select
from sqlalchemy.engine import Connection
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import SessionLocal
from app.models.kip import HISOBLANADIGAN_HOLATLAR, Kip
from app.models.mahsulot import Mahsulot
from app.models.partiya import Partiya
from app.services import advisory_lock
from app.services.davr import mavsum_boshi, sargable_oraliq
from app.services.telegram import statistika_xabari

logger = logging.getLogger("rejalashtiruvchi")

_scheduler = BackgroundScheduler(timezone=settings.VAQT_ZONASI)

# Ko'p-worker himoyasi (audit topilmasi) — qarang app/services/advisory_lock.py
# va telegram_polling.py'dagi bir xil naqsh. Qiymat telegram_polling.py'dagi
# LOCK_KALITI'dan ATAYLAB farqli — ikkalasi bir-biriga ta'sir qilmasligi kerak.
LOCK_KALITI = 72710_0002

_lock_ulanishi: Connection | None = None


def kecha_sanasi(bugun: date | None = None) -> date:
    """Hisobot doim TUGAGAN kunni (kecha) qamrab oladi — standart 08:30'da
    yuborilganda "bugungi kun" hali deyarli boshlanmagan/juda erta bo'ladi,
    shuning uchun "kechagi TO'LIQ kun" ma'lumoti beriladi. `bugun`
    (ixtiyoriy) faqat testlar uchun — berilmasa haqiqiy joriy sana
    ishlatiladi."""
    return (bugun or date.today()) - timedelta(days=1)


def _mahsulot_boyicha_qatorlar(db: Session, boshlanish: date, tugash: date) -> list[tuple[str, int, float]]:
    """`[boshlanish, tugash]` (ikkalasi ham qamrab olinadi) oralig'ida
    hisoblanadigan kiplarni mahsulot bo'yicha guruhlab qaytaradi."""
    pastki, yuqori = sargable_oraliq(boshlanish, tugash)
    return db.execute(
        select(Mahsulot.nomi, func.count(Kip.id), func.coalesce(func.sum(Kip.ogirlik), 0))
        .join(Partiya, Partiya.mahsulot_id == Mahsulot.id)
        .join(Kip, Kip.partiya_id == Partiya.id)
        .where(Kip.holati.in_(HISOBLANADIGAN_HOLATLAR), Kip.vaqt >= pastki, Kip.vaqt < yuqori)
        .group_by(Mahsulot.nomi)
    ).all()


def _jami_soni_va_ogirlik(db: Session, boshlanish: date, tugash: date) -> tuple[int, float]:
    """`[boshlanish, tugash]` oralig'idagi hisoblanadigan kiplarning jami
    soni va og'irligi (mahsulot bo'yicha ajratmasdan)."""
    pastki, yuqori = sargable_oraliq(boshlanish, tugash)
    soni, kg = db.execute(
        select(func.count(Kip.id), func.coalesce(func.sum(Kip.ogirlik), 0)).where(
            Kip.holati.in_(HISOBLANADIGAN_HOLATLAR), Kip.vaqt >= pastki, Kip.vaqt < yuqori
        )
    ).one()
    return soni, float(kg)


def _hisobot_matni(
    kecha: date,
    qatorlar: list[tuple[str, int, float]],
    mavsum_boshlanish: date,
    mavsum_soni: int,
    mavsum_kg: float,
) -> str:
    """Ikki bo'limli xabar matni: kechagi kun (mahsulot bo'yicha ajratilgan)
    va mavsum boshidan hozirgacha jamlanma (ajratmasdan, jami son/og'irlik)."""
    if not qatorlar:
        kecha_matni = f"📅 Kecha ({kecha.isoformat()}): hech narsa tortilmadi."
    else:
        qatorlar_matni = "\n".join(f"  {nomi}: {soni} ta, {float(kg):.1f} kg" for nomi, soni, kg in qatorlar)
        kecha_matni = f"📅 Kecha ({kecha.isoformat()}):\n{qatorlar_matni}"

    mavsum_matni = (
        f"📊 Mavsum boshidan ({mavsum_boshlanish.isoformat()} — {kecha.isoformat()}):\n"
        f"  Jami: {mavsum_soni} ta, {mavsum_kg:.1f} kg"
    )

    return f"{kecha_matni}\n\n{mavsum_matni}"


def _kunlik_hisobot_yubor() -> None:
    db = SessionLocal()
    try:
        kecha = kecha_sanasi()
        qatorlar = _mahsulot_boyicha_qatorlar(db, kecha, kecha)
        mavsum_boshlanish = mavsum_boshi(db, kecha)
        mavsum_soni, mavsum_kg = _jami_soni_va_ogirlik(db, mavsum_boshlanish, kecha)
        matn = _hisobot_matni(kecha, qatorlar, mavsum_boshlanish, mavsum_soni, mavsum_kg)

        statistika_xabari(db, matn)
    except Exception:
        logger.exception("Kunlik hisobot yuborishda xato")
    finally:
        db.close()


def ishga_tushir() -> None:
    """Ko'p-worker himoyasi: avval advisory lock olishga urinadi — band
    bo'lsa (boshqa worker/instance allaqachon rejalashtirgan) bu chaqiruv
    HECH NARSA QILMAYDI (faqat log). Shu tufayli `uvicorn --workers N`
    bilan ishga tushirilsa ham kunlik hisobot faqat BIR MARTA yuboriladi
    (N marta emas)."""
    global _lock_ulanishi
    if _lock_ulanishi is None:
        _lock_ulanishi = advisory_lock.olishga_urin(LOCK_KALITI, "Kunlik hisobot rejalashtiruvchisi")
        if _lock_ulanishi is None:
            return

    soat, daqiqa = (int(qism) for qism in settings.KUNLIK_HISOBOT_VAQTI.split(":"))
    _scheduler.add_job(
        _kunlik_hisobot_yubor,
        CronTrigger(hour=soat, minute=daqiqa),
        id="kunlik_hisobot",
        replace_existing=True,
    )
    if not _scheduler.running:
        _scheduler.start()
    logger.info("Kunlik hisobot rejalashtiruvchisi ishga tushdi (%s)", settings.KUNLIK_HISOBOT_VAQTI)


def toxtat() -> None:
    global _lock_ulanishi
    if _scheduler.running:
        _scheduler.shutdown(wait=False)
    advisory_lock.boshatish(_lock_ulanishi, "Kunlik hisobot rejalashtiruvchisi")
    _lock_ulanishi = None

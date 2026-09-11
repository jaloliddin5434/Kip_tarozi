import logging
from datetime import date

from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger
from sqlalchemy import func, select
from sqlalchemy.engine import Connection

from app.core.config import settings
from app.core.database import SessionLocal
from app.models.kip import HISOBLANADIGAN_HOLATLAR, Kip
from app.models.mahsulot import Mahsulot
from app.models.partiya import Partiya
from app.services import advisory_lock
from app.services.telegram import statistika_xabari

logger = logging.getLogger("rejalashtiruvchi")

_scheduler = BackgroundScheduler(timezone=settings.VAQT_ZONASI)

# Ko'p-worker himoyasi (audit topilmasi) — qarang app/services/advisory_lock.py
# va telegram_polling.py'dagi bir xil naqsh. Qiymat telegram_polling.py'dagi
# LOCK_KALITI'dan ATAYLAB farqli — ikkalasi bir-biriga ta'sir qilmasligi kerak.
LOCK_KALITI = 72710_0002

_lock_ulanishi: Connection | None = None


def _kunlik_hisobot_yubor() -> None:
    db = SessionLocal()
    try:
        bugun = date.today()
        qatorlar = db.execute(
            select(Mahsulot.nomi, func.count(Kip.id), func.coalesce(func.sum(Kip.ogirlik), 0))
            .join(Partiya, Partiya.mahsulot_id == Mahsulot.id)
            .join(Kip, Kip.partiya_id == Partiya.id)
            .where(Kip.holati.in_(HISOBLANADIGAN_HOLATLAR), func.date(Kip.vaqt) == bugun)
            .group_by(Mahsulot.nomi)
        ).all()

        if not qatorlar:
            matn = f"📊 Kunlik hisobot ({bugun.isoformat()}): bugun hech narsa tortilmadi."
        else:
            qatorlar_matni = "\n".join(f"  {nomi}: {soni} ta, {float(kg):.1f} kg" for nomi, soni, kg in qatorlar)
            matn = f"📊 Kunlik hisobot ({bugun.isoformat()}):\n{qatorlar_matni}"

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

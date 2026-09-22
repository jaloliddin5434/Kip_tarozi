import logging
import threading
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
from app.models.sozlama import Sozlama
from app.services import advisory_lock
from app.services.davr import mavsum_boshi, sargable_oraliq
from app.services.telegram import statistika_xabari

logger = logging.getLogger("rejalashtiruvchi")

_scheduler = BackgroundScheduler(timezone=settings.VAQT_ZONASI)

# Ko'p-worker himoyasi (audit topilmasi) — qarang app/services/advisory_lock.py
# va telegram_polling.py'dagi bir xil naqsh. Qiymat telegram_polling.py'dagi
# LOCK_KALITI'dan ATAYLAB farqli — ikkalasi bir-biriga ta'sir qilmasligi kerak.
LOCK_KALITI = 72710_0002

# Har bir MUVAFFAQIYATLI yuborilgan kunlik hisobotdan keyin shu sozlamaga
# o'sha hisobot qamragan "kecha" sanasi yoziladi — backend qayta ishga
# tushganda o'tkazib yuborilgan kunlarni aniqlash uchun ishlatiladi (qarang
# _otkazib_yuborilgan_kunlarni_qoplash).
OXIRGI_SANA_KALITI = "kunlik_hisobot_oxirgi_yuborilgan_sana"

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


def _qatorlar_matni(qatorlar: list[tuple[str, int, float]]) -> str:
    """Mahsulot bo'yicha guruhlangan qatorlarni "  Nomi: N ta, X kg" ko'rinishida,
    har biri alohida qatorda chiqaradi."""
    return "\n".join(f"  {nomi}: {soni} ta, {float(kg):.1f} kg" for nomi, soni, kg in qatorlar)


def _hisobot_matni(
    kecha: date,
    kecha_qatorlari: list[tuple[str, int, float]],
    mavsum_boshlanish: date,
    mavsum_qatorlari: list[tuple[str, int, float]],
) -> str:
    """Ikki bo'limli xabar matni — IKKALASI HAM mahsulot bo'yicha ajratilgan:
    kechagi kun va mavsum boshidan hozirgacha. Mavsum bo'limi oxirida,
    qulaylik uchun, umumiy jamlanma qatori ham qo'shiladi."""
    if not kecha_qatorlari:
        kecha_matni = f"📅 Kecha ({kecha.isoformat()}): hech narsa tortilmadi."
    else:
        kecha_matni = f"📅 Kecha ({kecha.isoformat()}):\n{_qatorlar_matni(kecha_qatorlari)}"

    mavsum_sarlavha = f"📊 Mavsum boshidan ({mavsum_boshlanish.isoformat()} — {kecha.isoformat()})"
    if not mavsum_qatorlari:
        mavsum_matni = f"{mavsum_sarlavha}: hech narsa tortilmadi."
    else:
        jami_soni = sum(soni for _nomi, soni, _kg in mavsum_qatorlari)
        jami_kg = sum(float(kg) for _nomi, _soni, kg in mavsum_qatorlari)
        mavsum_matni = (
            f"{mavsum_sarlavha}:\n"
            f"{_qatorlar_matni(mavsum_qatorlari)}\n"
            f"  (jami: {jami_soni} ta, {jami_kg:.1f} kg)"
        )

    return f"{kecha_matni}\n\n{mavsum_matni}"


def _oxirgi_yuborilgan_sanani_ol(db: Session) -> date | None:
    """`OXIRGI_SANA_KALITI` sozlamasini o'qiydi. Sozlama yo'q, bo'sh yoki
    noto'g'ri formatda bo'lsa — `None` (chaqiruvchi buni "hali hech qachon
    yuborilmagan" deb talqin qilishi kerak)."""
    sozlama = db.get(Sozlama, OXIRGI_SANA_KALITI)
    if sozlama is None or not sozlama.qiymat:
        return None
    try:
        return date.fromisoformat(sozlama.qiymat.strip())
    except ValueError:
        logger.warning("%s sozlamasi noto'g'ri formatda (%r)", OXIRGI_SANA_KALITI, sozlama.qiymat)
        return None


def _oxirgi_yuborilgan_sanani_yangila(db: Session, sana: date) -> None:
    sozlama = db.get(Sozlama, OXIRGI_SANA_KALITI)
    if sozlama is None:
        db.add(
            Sozlama(
                kalit=OXIRGI_SANA_KALITI,
                qiymat=sana.isoformat(),
                tavsif="Oxirgi muvaffaqiyatli yuborilgan kunlik Telegram hisoboti qamragan 'kecha' sanasi (avtomatik, qo'lda o'zgartirmang)",
            )
        )
    else:
        sozlama.qiymat = sana.isoformat()
    db.commit()


def _kunlik_hisobot_yubor(kecha: date | None = None) -> bool:
    """`kecha` berilmasa — haqiqiy "kecha" (standart kunlik vazifa). Berilsa —
    o'sha ANIQ kun uchun hisobot yasaydi (o'tkazib yuborilgan kunlarni
    qoplashda ishlatiladi, qarang _otkazib_yuborilgan_kunlarni_qoplash).
    Muvaffaqiyatli yuborilgan bo'lsa — OXIRGI_SANA_KALITI sozlamasini shu
    kunga yangilaydi va `True` qaytaradi; aks holda `False`."""
    db = SessionLocal()
    try:
        kecha = kecha if kecha is not None else kecha_sanasi()
        kecha_qatorlari = _mahsulot_boyicha_qatorlar(db, kecha, kecha)
        mavsum_boshlanish = mavsum_boshi(db, kecha)
        mavsum_qatorlari = _mahsulot_boyicha_qatorlar(db, mavsum_boshlanish, kecha)
        matn = _hisobot_matni(kecha, kecha_qatorlari, mavsum_boshlanish, mavsum_qatorlari)

        muvaffaqiyat = statistika_xabari(db, matn)
        if muvaffaqiyat:
            _oxirgi_yuborilgan_sanani_yangila(db, kecha)
        return bool(muvaffaqiyat)
    except Exception:
        logger.exception("Kunlik hisobot yuborishda xato")
        return False
    finally:
        db.close()


def _otkazib_yuborilgan_kunlarni_qoplash() -> None:
    """Backend ishga tushganda (`ishga_tushir()` ichida, faqat advisory
    lockni ushlagan BITTA worker/instance'da — qarang pastda) BIR MARTA
    chaqiriladi. `OXIRGI_SANA_KALITI` bilan haqiqiy "kecha" orasida
    o'tkazib yuborilgan kun(lar) bo'lsa (masalan backend/internet uzoq vaqt
    ishlamagan), HAR BIRI uchun ALOHIDA kunlik hisobot yasab yuboradi —
    xuddi shu kun uchun `_kunlik_hisobot_yubor(kun)` chaqirib.

    Birinchi marta ishga tushirilganda (sozlama hali umuman yo'q) HECH
    NARSA qilmaydi — aks holda tizim birinchi marta o'rnatilganda "mavsum
    boshidan hozirgacha" bo'lgan barcha kunlar uchun keraksiz ko'p xabar
    yuborib yuborardi.

    `settings.KUNLIK_HISOBOT_QOPLASH_MAX_KUN`dan ko'p kun o'tkazib
    yuborilgan bo'lsa (masalan oylab backend ishlamagan) — xavfsizlik
    uchun faqat OXIRGI shuncha kun qoplanadi, qolgani haqida bitta
    ogohlantirish xabari yuboriladi (Telegramni yuzlab eski xabar bilan
    to'ldirmaslik uchun)."""
    db = SessionLocal()
    try:
        oxirgi = _oxirgi_yuborilgan_sanani_ol(db)
    finally:
        db.close()

    if oxirgi is None:
        logger.info(
            "Kunlik hisobot hali hech qachon yuborilmagan (%s sozlamasi yo'q) — "
            "o'tkazib yuborilgan kunlarni qoplash o'tkazib yuboriladi (birinchi ishga tushirish).",
            OXIRGI_SANA_KALITI,
        )
        return

    bugungi_kecha = kecha_sanasi()
    jami_otkazilgan_kun = (bugungi_kecha - oxirgi).days
    if jami_otkazilgan_kun <= 0:
        return  # hech narsa o'tkazib yuborilmagan — oxirgi hisobot allaqachon "kecha"ni qamraydi

    max_kun = settings.KUNLIK_HISOBOT_QOPLASH_MAX_KUN
    juda_kop_otkazilganmi = jami_otkazilgan_kun > max_kun
    birinchi_qoplanadigan = (bugungi_kecha - timedelta(days=max_kun - 1)) if juda_kop_otkazilganmi else (oxirgi + timedelta(days=1))

    logger.warning(
        "%d ta o'tkazib yuborilgan kunlik hisobot topildi (oxirgi yuborilgan: %s, kecha: %s) — qoplanmoqda.",
        jami_otkazilgan_kun,
        oxirgi.isoformat(),
        bugungi_kecha.isoformat(),
    )

    qoplangan_son = 0
    kun = birinchi_qoplanadigan
    while kun <= bugungi_kecha:
        logger.info("O'tkazib yuborilgan kunlik hisobot qoplanmoqda: %s", kun.isoformat())
        if _kunlik_hisobot_yubor(kun):
            qoplangan_son += 1
        else:
            logger.warning("O'tkazib yuborilgan %s kuni uchun hisobotni qoplab bo'lmadi.", kun.isoformat())
        kun += timedelta(days=1)

    if juda_kop_otkazilganmi:
        db = SessionLocal()
        try:
            statistika_xabari(
                db,
                f"⚠️ Diqqat: {jami_otkazilgan_kun} kunlik hisobot o'tkazib yuborilgan edi "
                f"(juda ko'p) — faqat oxirgi {max_kun} kuni qoplab yuborildi.",
            )
        finally:
            db.close()

    logger.info("O'tkazib yuborilgan kunlarni qoplash tugadi — %d ta kunlik hisobot yuborildi.", qoplangan_son)


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

        # O'tkazib yuborilgan kunlarni qoplash — shu lockni ushlagan (demak
        # kunlik hisobot uchun javobgar) worker'da, FAQAT BIR MARTA (shu
        # `if` blokidan — lock ENDI OLINGANDA). Alohida oqimda (thread) —
        # bir nechta Telegram so'rovi (har biri sekundlab davom etishi
        # mumkin) FastAPI lifespan/startup'ni bloklamasin, xuddi
        # telegram_polling.py'dagi naqsh bilan bir xil sabab bilan.
        threading.Thread(
            target=_otkazib_yuborilgan_kunlarni_qoplash,
            name="kunlik-hisobot-qoplash",
            daemon=True,
        ).start()

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

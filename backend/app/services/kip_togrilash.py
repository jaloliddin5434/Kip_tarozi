"""Operator "kip to'g'rilash" zayavkasi — kamera_tasdiq.py bilan bir xil
tasdiqlash/rad-etish naqshi, faqat kip yaratish o'rniga mavjud kipni
`kip_tahrirlash.kipni_tahrir_qil()` orqali TAHRIRLAYDI (shu bilan surat
fayli ham, kerak bo'lsa, to'g'ri yangi joyga ko'chadi).
"""

import logging
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.foydalanuvchi import Foydalanuvchi, Rol
from app.models.kip import Kip
from app.models.kip_togrilash import KipTogrilashHolati, KipTogrilashZayavkasi
from app.models.mahsulot import Mahsulot
from app.models.partiya import Partiya
from app.services.kip_tahrirlash import kipni_tahrir_qil

logger = logging.getLogger("kip_togrilash")


def zayavka_yarat(
    db: Session,
    *,
    kip: Kip,
    operator_id: int,
    yangi_mahsulot: Mahsulot,
    yangi_partiya: Partiya,
    sabab: str,
) -> KipTogrilashZayavkasi:
    """Yangi to'g'rilash zayavkasi yaratadi — eski_mahsulot/eski_partiya
    zayavka yaratilgan paytdagi holatning SNAPSHOT'i (keyinroq kip boshqa
    yo'l bilan o'zgarib ketsa ham, ro'yxatda "nimadan nimaga" ko'rinib
    tursin uchun)."""
    eski_partiya = db.get(Partiya, kip.partiya_id)
    zayavka = KipTogrilashZayavkasi(
        kip_id=kip.id,
        operator_id=operator_id,
        eski_mahsulot_id=eski_partiya.mahsulot_id,
        eski_partiya_id=eski_partiya.id,
        yangi_mahsulot_id=yangi_mahsulot.id,
        yangi_partiya_id=yangi_partiya.id,
        sabab=sabab,
    )
    db.add(zayavka)
    db.flush()
    return zayavka


def _audit_uchun_foydalanuvchi_id(db: Session, hal_qilgan_id: int | None) -> int:
    """kip_tahrirlash.kipni_tahrir_qil() AuditLog uchun HAQIQIY (NOT NULL)
    foydalanuvchi id talab qiladi. Panel orqali hal_qilgan_id doim mavjud;
    Telegram orqali esa Telegram foydalanuvchisi bizning admin jadvalimizda
    aks etmagani uchun None keladi — bu holda birinchi faol admin hisobiga
    yoziladi (chat allaqachon faqat adminlar ko'radigan ogohlantirish kanali)."""
    if hal_qilgan_id is not None:
        return hal_qilgan_id
    zaxira_admin_id = db.scalar(select(Foydalanuvchi.id).where(Foydalanuvchi.rol == Rol.admin).order_by(Foydalanuvchi.id))
    if zaxira_admin_id is None:
        raise RuntimeError("Kip to'g'rilash zayavkasini audit qilish uchun kamida bitta admin hisobi kerak")
    return zaxira_admin_id


def zayavkani_hal_qil(
    db: Session,
    zayavka_id: int,
    *,
    tasdiqlansinmi: bool,
    hal_qilgan_id: int | None = None,
    manba: str = "panel",
    izoh: str | None = None,
) -> tuple[KipTogrilashZayavkasi | None, Kip | None]:
    """So'rovni tasdiqlaydi yoki rad etadi. IDEMPOTENT — allaqachon hal
    qilingan bo'lsa hech narsa o'zgarmay, mavjud (zayavka, kip) juftini
    qaytaradi. Zayavka topilmasa (None, None)."""
    zayavka = db.execute(
        select(KipTogrilashZayavkasi).where(KipTogrilashZayavkasi.id == zayavka_id).with_for_update()
    ).scalar_one_or_none()
    if zayavka is None:
        return None, None

    if zayavka.holati != KipTogrilashHolati.kutilmoqda:
        kip = db.get(Kip, zayavka.kip_id)
        return zayavka, kip

    hozir = datetime.now(timezone.utc)

    if not tasdiqlansinmi:
        zayavka.holati = KipTogrilashHolati.rad_etilgan
        zayavka.hal_qilgan_id = hal_qilgan_id
        zayavka.hal_qilingan_vaqt = hozir
        zayavka.hal_qilish_manbasi = manba
        zayavka.izoh = izoh
        db.flush()
        logger.info("Kip to'g'rilash zayavkasi #%s RAD ETILDI (%s)", zayavka.id, manba)
        return zayavka, None

    kip = db.get(Kip, zayavka.kip_id)
    yangi_partiya = db.get(Partiya, zayavka.yangi_partiya_id)
    kipni_tahrir_qil(
        db,
        kip,
        yangi_ogirlik=None,
        yangi_partiya=yangi_partiya,
        sabab=zayavka.sabab,
        foydalanuvchi_id=_audit_uchun_foydalanuvchi_id(db, hal_qilgan_id),
    )

    zayavka.holati = KipTogrilashHolati.tasdiqlangan
    zayavka.hal_qilgan_id = hal_qilgan_id
    zayavka.hal_qilingan_vaqt = hozir
    zayavka.hal_qilish_manbasi = manba
    zayavka.izoh = izoh
    db.flush()
    logger.info("Kip to'g'rilash zayavkasi #%s TASDIQLANDI (%s) -> kip #%s", zayavka.id, manba, kip.id)
    return zayavka, kip

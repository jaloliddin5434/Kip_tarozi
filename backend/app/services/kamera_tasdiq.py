"""Kamera surat ololmaganda operatorni bloklab, Admin ruxsatini kutish oqimi.

`kiplar.saqlash()` kamera sozlangan-u surat ololmasa shu yerdagi `sorov_yarat()`
ni chaqiradi (kip saqlanmaydi). Admin panel yoki (2-bosqichda) Telegram tugmasi
`sorovni_hal_qil()` ni chaqiradi — tasdiqlansa kip SURATSIZ yoziladi.
"""

import logging
from datetime import datetime, timezone

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models.kamera_tasdiq import KameraTasdiqHolati, KameraTasdiqSorovi
from app.models.kip import Kip
from app.models.partiya import Partiya

logger = logging.getLogger("kamera_tasdiq")


def sorov_yarat(
    db: Session,
    *,
    mijoz_id: str,
    partiya_id: int,
    ogirlik: float,
    smena,
    operator_id: int,
    mahalliy_vaqt: datetime,
    stansiya_id: int | None,
    majburiy: bool,
) -> KameraTasdiqSorovi:
    """Bloklovchi "kamera tasdiq" so'rovini yaratadi. Idempotent: shu mijoz_id
    bilan so'rov allaqachon bo'lsa (operator qayta yuborgan) — o'shani qaytaradi."""
    mavjud = db.scalar(select(KameraTasdiqSorovi).where(KameraTasdiqSorovi.mijoz_id == mijoz_id))
    if mavjud is not None:
        return mavjud

    sorov = KameraTasdiqSorovi(
        mijoz_id=mijoz_id,
        partiya_id=partiya_id,
        ogirlik=ogirlik,
        smena=smena,
        operator_id=operator_id,
        mahalliy_vaqt=mahalliy_vaqt,
        stansiya_id=stansiya_id,
        majburiy=majburiy,
    )
    db.add(sorov)
    db.flush()
    return sorov


def _keyingi_kip_raqami(db: Session, partiya_id: int) -> int:
    # Partiya qatorini qulflaymiz — bir vaqtda kelgan boshqa saqlash bir xil
    # raqamni olmasin (kiplar.py'dagi bilan bir xil mantiq).
    db.execute(select(Partiya.id).where(Partiya.id == partiya_id).with_for_update())
    oxirgi = db.scalar(select(func.max(Kip.kip_raqami)).where(Kip.partiya_id == partiya_id))
    return (oxirgi or 0) + 1


def sorovni_hal_qil(
    db: Session,
    sorov_id: int,
    *,
    tasdiqlansinmi: bool,
    hal_qilgan_id: int | None = None,
    manba: str = "panel",
    izoh: str | None = None,
) -> tuple[KameraTasdiqSorovi | None, Kip | None]:
    """So'rovni tasdiqlaydi yoki rad etadi. IDEMPOTENT: allaqachon hal qilingan
    bo'lsa hech narsa o'zgartirmay, mavjud (so'rov, kip) juftini qaytaradi.
    So'rov topilmasa (None, None).

    Tasdiqlanganda kip SURATSIZ yoziladi. Qatorni `with_for_update` bilan
    qulflaydi — panel va Telegram bir vaqtda bosilsa ham kip bir marta yaratiladi.
    """
    sorov = db.execute(
        select(KameraTasdiqSorovi).where(KameraTasdiqSorovi.id == sorov_id).with_for_update()
    ).scalar_one_or_none()
    if sorov is None:
        return None, None

    if sorov.holati != KameraTasdiqHolati.kutilmoqda:
        mavjud_kip = db.get(Kip, sorov.kip_id) if sorov.kip_id else None
        return sorov, mavjud_kip

    hozir = datetime.now(timezone.utc)

    if not tasdiqlansinmi:
        sorov.holati = KameraTasdiqHolati.rad_etilgan
        sorov.hal_qilgan_id = hal_qilgan_id
        sorov.hal_qilingan_vaqt = hozir
        sorov.hal_qilish_manbasi = manba
        sorov.izoh = izoh
        db.flush()
        logger.info("Kamera tasdiq so'rovi #%s RAD ETILDI (%s)", sorov.id, manba)
        return sorov, None

    # --- Tasdiqlash: kipni suratsiz yozamiz ---
    # Operator online paytda qandaydir yo'l bilan kip allaqachon yozilib qolgan
    # bo'lsa (kam ehtimol) — uni bog'laymiz, dublikat yaratmaymiz.
    kip = db.scalar(select(Kip).where(Kip.mijoz_id == sorov.mijoz_id))
    if kip is None:
        kip = Kip(
            mijoz_id=sorov.mijoz_id,
            partiya_id=sorov.partiya_id,
            kip_raqami=_keyingi_kip_raqami(db, sorov.partiya_id),
            ogirlik=sorov.ogirlik,
            smena=sorov.smena,
            operator_id=sorov.operator_id,
            mahalliy_vaqt=sorov.mahalliy_vaqt,
            surat_yoli=None,
            stansiya_id=sorov.stansiya_id,
        )
        db.add(kip)
        db.flush()

    sorov.holati = KameraTasdiqHolati.tasdiqlangan
    sorov.kip_id = kip.id
    sorov.hal_qilgan_id = hal_qilgan_id
    sorov.hal_qilingan_vaqt = hozir
    sorov.hal_qilish_manbasi = manba
    sorov.izoh = izoh
    db.flush()
    logger.info("Kamera tasdiq so'rovi #%s TASDIQLANDI (%s) -> kip #%s", sorov.id, manba, kip.id)
    return sorov, kip

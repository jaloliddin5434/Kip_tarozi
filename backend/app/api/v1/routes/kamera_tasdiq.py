from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import rollarga_ruxsat
from app.core.database import get_db
from app.models.foydalanuvchi import Foydalanuvchi, Rol
from app.models.kamera_tasdiq import KameraTasdiqHolati, KameraTasdiqSorovi
from app.models.mahsulot import Mahsulot
from app.models.partiya import Partiya
from app.schemas.kamera_tasdiq import (
    KameraTasdiqHolatJavob,
    KameraTasdiqRadEtish,
    KameraTasdiqRoyxatJavob,
)
from app.schemas.sahifalash import Sahifalangan
from app.services import kamera_tasdiq
from app.services.davr import sargable_pastki, sargable_yuqori

router = APIRouter(prefix="/kamera-tasdiq", tags=["kamera-tasdiq"])


@router.get("/mening-kutilayotganim", response_model=KameraTasdiqHolatJavob | None)
def mening_kutilayotganim(
    db: Session = Depends(get_db),
    foydalanuvchi: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.operator)),
) -> KameraTasdiqSorovi | None:
    """Operator ekrani (5s'lik blok-tekshiruvi) shu orqali: agar operatorda hali
    hal qilinmagan "kamera tasdiq" so'rovi bo'lsa — uni qaytaradi va operator
    qayta bloklanadi (ilova qayta ochilsa ham blok tiklanadi)."""
    return db.scalar(
        select(KameraTasdiqSorovi)
        .where(
            KameraTasdiqSorovi.operator_id == foydalanuvchi.id,
            KameraTasdiqSorovi.holati == KameraTasdiqHolati.kutilmoqda,
        )
        .order_by(KameraTasdiqSorovi.vaqt.desc())
        .limit(1)
    )


@router.get("/{sorov_id}/holat", response_model=KameraTasdiqHolatJavob)
def holat(
    sorov_id: int,
    db: Session = Depends(get_db),
    foydalanuvchi: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.operator, Rol.admin)),
) -> KameraTasdiqSorovi:
    """Operator bloklovchi dialogda har bir necha soniyada shu endpointni
    so'raydi. Operator faqat O'Z so'rovini ko'ra oladi; admin — har qanday."""
    sorov = db.get(KameraTasdiqSorovi, sorov_id)
    if sorov is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="So'rov topilmadi")
    if foydalanuvchi.rol != Rol.admin and sorov.operator_id != foydalanuvchi.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Bu so'rov sizniki emas")
    return sorov


@router.get("", response_model=Sahifalangan[KameraTasdiqRoyxatJavob])
def royxat(
    holati: KameraTasdiqHolati | None = Query(None),
    sana_dan: date | None = Query(None),
    sana_gacha: date | None = Query(None),
    sahifa: int = Query(1, ge=1),
    sahifa_hajmi: int = Query(50, ge=1, le=500),
    db: Session = Depends(get_db),
    _: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.admin)),
) -> Sahifalangan[KameraTasdiqRoyxatJavob]:
    """Admin panel — "Kamera tasdiqlari" ro'yxati. Standart: eng yangi birinchi.
    `holati` berilmasa hammasi (kutilayotgan + hal qilingan) qaytadi."""
    hal_qilgan = Foydalanuvchi.__table__.alias("hal_qilgan")
    operator = Foydalanuvchi.__table__.alias("operator")

    sorov = (
        select(KameraTasdiqSorovi, Mahsulot.nomi, Partiya.partiya_raqami, operator.c.ism, hal_qilgan.c.ism)
        .join(Partiya, KameraTasdiqSorovi.partiya_id == Partiya.id)
        .join(Mahsulot, Partiya.mahsulot_id == Mahsulot.id)
        .join(operator, KameraTasdiqSorovi.operator_id == operator.c.id)
        .outerjoin(hal_qilgan, KameraTasdiqSorovi.hal_qilgan_id == hal_qilgan.c.id)
    )
    if holati is not None:
        sorov = sorov.where(KameraTasdiqSorovi.holati == holati)
    if sana_dan is not None:
        sorov = sorov.where(KameraTasdiqSorovi.vaqt >= sargable_pastki(sana_dan))
    if sana_gacha is not None:
        sorov = sorov.where(KameraTasdiqSorovi.vaqt < sargable_yuqori(sana_gacha))

    jami = db.scalar(select(func.count()).select_from(sorov.subquery())) or 0

    qatorlar = db.execute(
        sorov.order_by(KameraTasdiqSorovi.vaqt.desc(), KameraTasdiqSorovi.id.desc())
        .offset((sahifa - 1) * sahifa_hajmi)
        .limit(sahifa_hajmi)
    ).all()

    items = [
        KameraTasdiqRoyxatJavob(
            id=s.id,
            vaqt=s.vaqt,
            smena=s.smena,
            ogirlik=float(s.ogirlik),
            mahsulot_nomi=mahsulot_nomi,
            partiya_raqami=partiya_raqami,
            operator_ism=operator_ism,
            holati=s.holati,
            kip_id=s.kip_id,
            hal_qilingan_vaqt=s.hal_qilingan_vaqt,
            hal_qilgan_ism=hal_qilgan_ism,
            hal_qilish_manbasi=s.hal_qilish_manbasi,
            izoh=s.izoh,
        )
        for s, mahsulot_nomi, partiya_raqami, operator_ism, hal_qilgan_ism in qatorlar
    ]
    return Sahifalangan(items=items, jami=jami, sahifa=sahifa, sahifa_hajmi=sahifa_hajmi)


@router.post("/{sorov_id}/tasdiqlash", response_model=KameraTasdiqHolatJavob)
def tasdiqlash(
    sorov_id: int,
    db: Session = Depends(get_db),
    foydalanuvchi: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.admin)),
) -> KameraTasdiqSorovi:
    """Admin tasdiqlaydi — kip SURATSIZ avtomatik saqlanadi, operator blokdan
    chiqadi. Idempotent."""
    sorov, _kip = kamera_tasdiq.sorovni_hal_qil(
        db, sorov_id, tasdiqlansinmi=True, hal_qilgan_id=foydalanuvchi.id, manba="panel"
    )
    if sorov is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="So'rov topilmadi")
    db.commit()
    db.refresh(sorov)
    return sorov


@router.post("/{sorov_id}/rad-etish", response_model=KameraTasdiqHolatJavob)
def rad_etish(
    sorov_id: int,
    malumot: KameraTasdiqRadEtish | None = None,
    db: Session = Depends(get_db),
    foydalanuvchi: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.admin)),
) -> KameraTasdiqSorovi:
    """Admin rad etadi — kip saqlanmaydi, operator "qaytadan urinib ko'ring"
    xabarini oladi. Idempotent."""
    sorov, _kip = kamera_tasdiq.sorovni_hal_qil(
        db,
        sorov_id,
        tasdiqlansinmi=False,
        hal_qilgan_id=foydalanuvchi.id,
        manba="panel",
        izoh=(malumot.izoh if malumot else None),
    )
    if sorov is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="So'rov topilmadi")
    db.commit()
    db.refresh(sorov)
    return sorov

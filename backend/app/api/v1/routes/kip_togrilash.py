from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import rollarga_ruxsat
from app.core.database import get_db
from app.models.foydalanuvchi import Foydalanuvchi, Rol
from app.models.kip import Kip
from app.models.kip_togrilash import KipTogrilashHolati, KipTogrilashZayavkasi
from app.models.mahsulot import Mahsulot
from app.models.partiya import Partiya
from app.schemas.kip_togrilash import (
    KipTogrilashHolatJavob,
    KipTogrilashRadEtish,
    KipTogrilashRoyxatJavob,
    KipTogrilashYaratish,
)
from app.schemas.sahifalash import Sahifalangan
from app.services import kip_togrilash
from app.services.kip_tahrirlash import KipTahrirlashTaqiqlangan
from app.services.telegram import surat_xabarini_yangila, xatolik_xabari_tugma_bilan

router = APIRouter(prefix="/kip-togrilash", tags=["kip-togrilash"])


@router.post("", response_model=KipTogrilashHolatJavob, status_code=status.HTTP_201_CREATED)
def yaratish(
    malumot: KipTogrilashYaratish,
    db: Session = Depends(get_db),
    foydalanuvchi: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.operator)),
) -> KipTogrilashZayavkasi:
    """Operator "Smena tarixi" ro'yxatidagi biror kip uchun mahsulot/partiya
    noto'g'ri tanlanganini bildiradi. Faqat O'Z SMENASIDAGI kip uchun
    (xuddi /kiplar/smena/royxat ko'rsatish qoidasi bilan bir xil — istalgan
    o'sha smenadagi operator, faqat yozuvni kiritgan operator emas)."""
    kip = db.get(Kip, malumot.kip_id)
    if kip is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Kip topilmadi")
    if kip.smena != foydalanuvchi.smena:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="Faqat o'z smenangizdagi kip uchun so'rov yubora olasiz"
        )

    yangi_mahsulot = db.scalar(select(Mahsulot).where(Mahsulot.kod == malumot.yangi_mahsulot_kodi))
    if yangi_mahsulot is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Mahsulot topilmadi")
    yangi_partiya = db.scalar(
        select(Partiya).where(
            Partiya.mahsulot_id == yangi_mahsulot.id,
            Partiya.partiya_raqami == malumot.yangi_partiya_raqami,
        )
    )
    if yangi_partiya is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Partiya topilmadi")

    try:
        zayavka = kip_togrilash.zayavka_yarat(
            db,
            kip=kip,
            operator_id=foydalanuvchi.id,
            yangi_mahsulot=yangi_mahsulot,
            yangi_partiya=yangi_partiya,
            sabab=malumot.sabab,
        )
    except KipTahrirlashTaqiqlangan as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    db.commit()
    db.refresh(zayavka)

    eski_partiya = db.get(Partiya, zayavka.eski_partiya_id)
    eski_mahsulot = db.get(Mahsulot, zayavka.eski_mahsulot_id)
    xatolik_xabari_tugma_bilan(
        db,
        "✏️ KIP TO'G'RILASH SO'RALDI\n"
        f"Kip №{kip.kip_raqami} (#{eski_partiya.partiya_raqami} {eski_mahsulot.nomi} -> "
        f"#{yangi_partiya.partiya_raqami} {yangi_mahsulot.nomi})\n"
        f"Smena: {foydalanuvchi.smena.value}\n"
        f"Sabab: {malumot.sabab}\n"
        f"Zayavka ID: {zayavka.id}",
        callback_prefiks="zayavka",
        obyekt_id=zayavka.id,
    )
    return zayavka


@router.get("", response_model=Sahifalangan[KipTogrilashRoyxatJavob])
def royxat(
    holati: KipTogrilashHolati | None = Query(None),
    sana_dan: date | None = Query(None),
    sana_gacha: date | None = Query(None),
    sahifa: int = Query(1, ge=1),
    sahifa_hajmi: int = Query(50, ge=1, le=500),
    db: Session = Depends(get_db),
    _: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.admin)),
) -> Sahifalangan[KipTogrilashRoyxatJavob]:
    """Admin panel — "Kip to'g'rilash so'rovlari" ro'yxati."""
    hal_qilgan = Foydalanuvchi.__table__.alias("hal_qilgan")
    operator = Foydalanuvchi.__table__.alias("operator")
    eski_mahsulot = Mahsulot.__table__.alias("eski_mahsulot")
    yangi_mahsulot = Mahsulot.__table__.alias("yangi_mahsulot")
    eski_partiya = Partiya.__table__.alias("eski_partiya")
    yangi_partiya = Partiya.__table__.alias("yangi_partiya")

    sorov = (
        select(
            KipTogrilashZayavkasi,
            Kip.kip_raqami,
            operator.c.ism,
            eski_mahsulot.c.nomi,
            eski_partiya.c.partiya_raqami,
            yangi_mahsulot.c.nomi,
            yangi_partiya.c.partiya_raqami,
            hal_qilgan.c.ism,
        )
        .join(Kip, KipTogrilashZayavkasi.kip_id == Kip.id)
        .join(operator, KipTogrilashZayavkasi.operator_id == operator.c.id)
        .join(eski_mahsulot, KipTogrilashZayavkasi.eski_mahsulot_id == eski_mahsulot.c.id)
        .join(yangi_mahsulot, KipTogrilashZayavkasi.yangi_mahsulot_id == yangi_mahsulot.c.id)
        .join(eski_partiya, KipTogrilashZayavkasi.eski_partiya_id == eski_partiya.c.id)
        .join(yangi_partiya, KipTogrilashZayavkasi.yangi_partiya_id == yangi_partiya.c.id)
        .outerjoin(hal_qilgan, KipTogrilashZayavkasi.hal_qilgan_id == hal_qilgan.c.id)
    )
    if holati is not None:
        sorov = sorov.where(KipTogrilashZayavkasi.holati == holati)
    if sana_dan is not None:
        sorov = sorov.where(func.date(KipTogrilashZayavkasi.vaqt) >= sana_dan)
    if sana_gacha is not None:
        sorov = sorov.where(func.date(KipTogrilashZayavkasi.vaqt) <= sana_gacha)

    jami = db.scalar(select(func.count()).select_from(sorov.subquery())) or 0

    qatorlar = db.execute(
        sorov.order_by(KipTogrilashZayavkasi.vaqt.desc(), KipTogrilashZayavkasi.id.desc())
        .offset((sahifa - 1) * sahifa_hajmi)
        .limit(sahifa_hajmi)
    ).all()

    items = [
        KipTogrilashRoyxatJavob(
            id=z.id,
            vaqt=z.vaqt,
            kip_id=z.kip_id,
            kip_raqami=kip_raqami,
            operator_ism=operator_ism,
            eski_mahsulot_nomi=eski_mahsulot_nomi,
            eski_partiya_raqami=eski_partiya_raqami,
            yangi_mahsulot_nomi=yangi_mahsulot_nomi,
            yangi_partiya_raqami=yangi_partiya_raqami,
            sabab=z.sabab,
            holati=z.holati,
            hal_qilingan_vaqt=z.hal_qilingan_vaqt,
            hal_qilgan_ism=hal_qilgan_ism,
            hal_qilish_manbasi=z.hal_qilish_manbasi,
            izoh=z.izoh,
        )
        for z, kip_raqami, operator_ism, eski_mahsulot_nomi, eski_partiya_raqami, yangi_mahsulot_nomi, yangi_partiya_raqami, hal_qilgan_ism in qatorlar
    ]
    return Sahifalangan(items=items, jami=jami, sahifa=sahifa, sahifa_hajmi=sahifa_hajmi)


@router.post("/{zayavka_id}/tasdiqlash", response_model=KipTogrilashHolatJavob)
def tasdiqlash(
    zayavka_id: int,
    db: Session = Depends(get_db),
    foydalanuvchi: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.admin)),
) -> KipTogrilashZayavkasi:
    """Admin tasdiqlaydi — kip mahsulot/partiyasi (va surati, kerak bo'lsa)
    yangilanadi. Idempotent."""
    try:
        zayavka, _kip, telegram_yangilash = kip_togrilash.zayavkani_hal_qil(
            db, zayavka_id, tasdiqlansinmi=True, hal_qilgan_id=foydalanuvchi.id, manba="panel"
        )
    except KipTahrirlashTaqiqlangan as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    if zayavka is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Zayavka topilmadi")
    db.commit()
    db.refresh(zayavka)
    # Telegram so'rovi COMMIT'dan KEYIN (4-QISM naqshi).
    if telegram_yangilash is not None:
        surat_xabarini_yangila(db, *telegram_yangilash)
    return zayavka


@router.post("/{zayavka_id}/rad-etish", response_model=KipTogrilashHolatJavob)
def rad_etish(
    zayavka_id: int,
    malumot: KipTogrilashRadEtish | None = None,
    db: Session = Depends(get_db),
    foydalanuvchi: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.admin)),
) -> KipTogrilashZayavkasi:
    """Admin rad etadi — kip o'zgarishsiz qoladi. Idempotent."""
    zayavka, _kip, _telegram_yangilash = kip_togrilash.zayavkani_hal_qil(
        db,
        zayavka_id,
        tasdiqlansinmi=False,
        hal_qilgan_id=foydalanuvchi.id,
        manba="panel",
        izoh=(malumot.izoh if malumot else None),
    )
    if zayavka is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Zayavka topilmadi")
    db.commit()
    db.refresh(zayavka)
    return zayavka

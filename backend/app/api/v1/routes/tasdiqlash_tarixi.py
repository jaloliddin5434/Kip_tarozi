from datetime import date

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import rollarga_ruxsat
from app.core.database import get_db
from app.models.foydalanuvchi import Foydalanuvchi, Rol
from app.models.kamera_tasdiq import KameraTasdiqHolati, KameraTasdiqSorovi
from app.models.kip import Kip
from app.models.kip_togrilash import KipTogrilashHolati, KipTogrilashZayavkasi
from app.models.mahsulot import Mahsulot
from app.models.partiya import Partiya
from app.schemas.sahifalash import Sahifalangan
from app.schemas.tasdiqlash_tarixi import TasdiqTarixiHolati, TasdiqTarixiYozuvi
from app.services import kamera_tasdiq
from app.services.davr import sargable_pastki, sargable_yuqori

router = APIRouter(prefix="/tasdiqlash-tarixi", tags=["tasdiqlash-tarixi"])


def _kamera_qatorlari(
    db: Session,
    holati: TasdiqTarixiHolati | None,
    sana_dan: date | None,
    sana_gacha: date | None,
    hal_qilingan_sana: date | None,
) -> list[TasdiqTarixiYozuvi]:
    hal_qilgan = Foydalanuvchi.__table__.alias("kamera_hal_qilgan")
    operator = Foydalanuvchi.__table__.alias("kamera_operator")

    sorov = (
        select(KameraTasdiqSorovi, Mahsulot.nomi, Partiya.partiya_raqami, operator.c.ism, hal_qilgan.c.ism)
        .join(Partiya, KameraTasdiqSorovi.partiya_id == Partiya.id)
        .join(Mahsulot, Partiya.mahsulot_id == Mahsulot.id)
        .join(operator, KameraTasdiqSorovi.operator_id == operator.c.id)
        .outerjoin(hal_qilgan, KameraTasdiqSorovi.hal_qilgan_id == hal_qilgan.c.id)
    )
    if holati is not None:
        sorov = sorov.where(KameraTasdiqSorovi.holati == KameraTasdiqHolati(holati.value))
    if sana_dan is not None:
        sorov = sorov.where(KameraTasdiqSorovi.vaqt >= sargable_pastki(sana_dan))
    if sana_gacha is not None:
        sorov = sorov.where(KameraTasdiqSorovi.vaqt < sargable_yuqori(sana_gacha))
    if hal_qilingan_sana is not None:
        sorov = sorov.where(
            KameraTasdiqSorovi.hal_qilingan_vaqt >= sargable_pastki(hal_qilingan_sana),
            KameraTasdiqSorovi.hal_qilingan_vaqt < sargable_yuqori(hal_qilingan_sana),
        )

    return [
        TasdiqTarixiYozuvi(
            tur="kamera",
            id=s.id,
            vaqt=s.vaqt,
            operator_ism=operator_ism,
            tavsif=f"{mahsulot_nomi} #{partiya_raqami}, {float(s.ogirlik):.1f} kg",
            sabab=None,
            holati=TasdiqTarixiHolati(s.holati.value),
            hal_qilingan_vaqt=s.hal_qilingan_vaqt,
            hal_qilgan_ism=hal_qilgan_ism,
            hal_qilish_manbasi=s.hal_qilish_manbasi,
            izoh=s.izoh,
            # Faqat hali HAL QILINMAGAN so'rovlar uchun hisoblanadi — GET
            # /kamera-tasdiq bilan bir xil naqsh (qarang shu faylning izohi).
            dublikat_shubhasi=(
                kamera_tasdiq.dublikat_shubhasi_bormi(db, s) if s.holati == KameraTasdiqHolati.kutilmoqda else False
            ),
        )
        for s, mahsulot_nomi, partiya_raqami, operator_ism, hal_qilgan_ism in db.execute(sorov).all()
    ]


def _kip_togrilash_qatorlari(
    db: Session,
    holati: TasdiqTarixiHolati | None,
    sana_dan: date | None,
    sana_gacha: date | None,
    hal_qilingan_sana: date | None,
) -> list[TasdiqTarixiYozuvi]:
    hal_qilgan = Foydalanuvchi.__table__.alias("togrilash_hal_qilgan")
    operator = Foydalanuvchi.__table__.alias("togrilash_operator")
    eski_mahsulot = Mahsulot.__table__.alias("tarixi_eski_mahsulot")
    yangi_mahsulot = Mahsulot.__table__.alias("tarixi_yangi_mahsulot")
    eski_partiya = Partiya.__table__.alias("tarixi_eski_partiya")
    yangi_partiya = Partiya.__table__.alias("tarixi_yangi_partiya")

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
        sorov = sorov.where(KipTogrilashZayavkasi.holati == KipTogrilashHolati(holati.value))
    if sana_dan is not None:
        sorov = sorov.where(KipTogrilashZayavkasi.vaqt >= sargable_pastki(sana_dan))
    if sana_gacha is not None:
        sorov = sorov.where(KipTogrilashZayavkasi.vaqt < sargable_yuqori(sana_gacha))
    if hal_qilingan_sana is not None:
        sorov = sorov.where(
            KipTogrilashZayavkasi.hal_qilingan_vaqt >= sargable_pastki(hal_qilingan_sana),
            KipTogrilashZayavkasi.hal_qilingan_vaqt < sargable_yuqori(hal_qilingan_sana),
        )

    natija = []
    for (
        z,
        kip_raqami,
        operator_ism,
        eski_mahsulot_nomi,
        eski_partiya_raqami,
        yangi_mahsulot_nomi,
        yangi_partiya_raqami,
        hal_qilgan_ism,
    ) in db.execute(sorov).all():
        natija.append(
            TasdiqTarixiYozuvi(
                tur="kip_togrilash",
                id=z.id,
                vaqt=z.vaqt,
                operator_ism=operator_ism,
                tavsif=(
                    f"Kip №{kip_raqami}: {eski_mahsulot_nomi} #{eski_partiya_raqami} -> "
                    f"{yangi_mahsulot_nomi} #{yangi_partiya_raqami}"
                ),
                sabab=z.sabab,
                holati=TasdiqTarixiHolati(z.holati.value),
                hal_qilingan_vaqt=z.hal_qilingan_vaqt,
                hal_qilgan_ism=hal_qilgan_ism,
                hal_qilish_manbasi=z.hal_qilish_manbasi,
                izoh=z.izoh,
            )
        )
    return natija


@router.get("", response_model=Sahifalangan[TasdiqTarixiYozuvi])
def royxat(
    holati: TasdiqTarixiHolati | None = Query(None),
    sana_dan: date | None = Query(None),
    sana_gacha: date | None = Query(None),
    hal_qilingan_sana: date | None = Query(
        None, description="Faqat shu kunda HAL QILINGAN (tasdiqlangan/rad etilgan) yozuvlar — kalendar uchun."
    ),
    sahifa: int = Query(1, ge=1),
    sahifa_hajmi: int = Query(50, ge=1, le=500),
    db: Session = Depends(get_db),
    _: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.admin)),
) -> Sahifalangan[TasdiqTarixiYozuvi]:
    """Admin panel — "Kamera tasdiqlari" va "Kip to'g'irlash so'rovlari"ni
    BITTA ro'yxatda birlashtiradi (`tur` maydoni orqali farqlanadi). Ikkala
    manba mustaqil so'ralib, Python darajasida `vaqt` bo'yicha kamayish
    tartibida birlashtiriladi va sahifalanadi — ikkala jadval hajmi ham
    (tasdiq/tuzatish navbatlari) kichik bo'lgani uchun bu haqiqiy SQL UNIONga
    qaraganda ANCHA soddaroq va bir xil kod ikkala turdagi so'rovni ham
    (`_kamera_qatorlari`/`_kip_togrilash_qatorlari`) mustaqil sinash imkonini
    beradi."""
    barchasi = _kamera_qatorlari(db, holati, sana_dan, sana_gacha, hal_qilingan_sana) + _kip_togrilash_qatorlari(
        db, holati, sana_dan, sana_gacha, hal_qilingan_sana
    )
    barchasi.sort(key=lambda y: (y.vaqt, y.id), reverse=True)

    jami = len(barchasi)
    boshlanish = (sahifa - 1) * sahifa_hajmi
    sahifadagilar = barchasi[boshlanish : boshlanish + sahifa_hajmi]
    return Sahifalangan(items=sahifadagilar, jami=jami, sahifa=sahifa, sahifa_hajmi=sahifa_hajmi)

from datetime import date

from fastapi import APIRouter, Depends, Query
from sqlalchemy import String, cast, func, or_, select
from sqlalchemy.orm import Session

from app.api.deps import rollarga_ruxsat
from app.core.database import get_db
from app.models.audit_log import AuditLog
from app.models.foydalanuvchi import Foydalanuvchi, Rol, Smena
from app.models.kip import Kip, KipHolati
from app.models.mahsulot import Mahsulot
from app.models.partiya import Partiya
from app.schemas.hujjat import AuditLogJavob, HujjatKipJavob
from app.schemas.sahifalash import Sahifalangan
from app.services.davr import sargable_pastki, sargable_yuqori
from app.services.media import surat_ommaviy_url

router = APIRouter(prefix="/hujjatlar", tags=["hujjatlar"])


@router.get("/kiplar", response_model=Sahifalangan[HujjatKipJavob])
def kiplar_royxati(
    sana_dan: date | None = Query(None),
    sana_gacha: date | None = Query(None),
    smena: Smena | None = Query(None),
    mahsulot_kodi: str | None = Query(None),
    partiya_raqami: int | None = Query(None),
    kip_raqami: int | None = Query(None),
    holati: KipHolati | None = Query(None),
    qidiruv: str | None = Query(None),
    sahifa: int = Query(1, ge=1),
    sahifa_hajmi: int = Query(50, ge=1, le=500),
    db: Session = Depends(get_db),
    _: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.admin, Rol.tayyor_mahsulotlar)),
) -> Sahifalangan[HujjatKipJavob]:
    sorov = (
        select(Kip, Partiya.partiya_raqami, Mahsulot.kod, Mahsulot.nomi, Foydalanuvchi.ism)
        .join(Partiya, Kip.partiya_id == Partiya.id)
        .join(Mahsulot, Partiya.mahsulot_id == Mahsulot.id)
        .join(Foydalanuvchi, Kip.operator_id == Foydalanuvchi.id)
    )
    if sana_dan is not None:
        sorov = sorov.where(Kip.vaqt >= sargable_pastki(sana_dan))
    if sana_gacha is not None:
        sorov = sorov.where(Kip.vaqt < sargable_yuqori(sana_gacha))
    if smena is not None:
        sorov = sorov.where(Kip.smena == smena)
    if mahsulot_kodi is not None:
        sorov = sorov.where(Mahsulot.kod == mahsulot_kodi)
    if partiya_raqami is not None:
        sorov = sorov.where(Partiya.partiya_raqami == partiya_raqami)
    if kip_raqami is not None:
        sorov = sorov.where(Kip.kip_raqami == kip_raqami)
    if holati is not None:
        sorov = sorov.where(Kip.holati == holati)
    if qidiruv is not None and qidiruv.strip():
        andoza = f"%{qidiruv.strip()}%"
        sorov = sorov.where(
            or_(Foydalanuvchi.ism.ilike(andoza), cast(Partiya.partiya_raqami, String).ilike(andoza))
        )

    jami = db.scalar(select(func.count()).select_from(sorov.subquery())) or 0

    sahifalangan_sorov = sorov.order_by(Kip.vaqt.desc()).offset((sahifa - 1) * sahifa_hajmi).limit(sahifa_hajmi)
    natijalar = db.execute(sahifalangan_sorov).all()

    items = [
        HujjatKipJavob(
            id=kip.id,
            mahsulot_kodi=mahsulot_kodi_,
            mahsulot_nomi=mahsulot_nomi,
            partiya_id=kip.partiya_id,
            partiya_raqami=partiya_raqami_,
            kip_raqami=kip.kip_raqami,
            ogirlik=float(kip.ogirlik),
            smena=kip.smena,
            operator_id=kip.operator_id,
            operator_ism=operator_ism,
            vaqt=kip.vaqt,
            surat_yoli=surat_ommaviy_url(kip.surat_yoli),
            holati=kip.holati,
        )
        for kip, partiya_raqami_, mahsulot_kodi_, mahsulot_nomi, operator_ism in natijalar
    ]
    return Sahifalangan(items=items, jami=jami, sahifa=sahifa, sahifa_hajmi=sahifa_hajmi)


@router.get("/audit", response_model=Sahifalangan[AuditLogJavob])
def audit_royxati(
    jadval_nomi: str | None = Query(None),
    sana_dan: date | None = Query(None),
    sana_gacha: date | None = Query(None),
    sahifa: int = Query(1, ge=1),
    sahifa_hajmi: int = Query(50, ge=1, le=500),
    db: Session = Depends(get_db),
    _: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.admin)),
) -> Sahifalangan[AuditLogJavob]:
    sorov = select(AuditLog, Foydalanuvchi.ism).join(Foydalanuvchi, AuditLog.foydalanuvchi_id == Foydalanuvchi.id)
    if jadval_nomi is not None:
        sorov = sorov.where(AuditLog.jadval_nomi == jadval_nomi)
    if sana_dan is not None:
        sorov = sorov.where(AuditLog.vaqt >= sargable_pastki(sana_dan))
    if sana_gacha is not None:
        sorov = sorov.where(AuditLog.vaqt < sargable_yuqori(sana_gacha))

    jami = db.scalar(select(func.count()).select_from(sorov.subquery())) or 0

    sahifalangan_sorov = sorov.order_by(AuditLog.vaqt.desc()).offset((sahifa - 1) * sahifa_hajmi).limit(sahifa_hajmi)
    natijalar = db.execute(sahifalangan_sorov).all()

    items = [
        AuditLogJavob(
            id=log.id,
            foydalanuvchi_id=log.foydalanuvchi_id,
            foydalanuvchi_ism=ism,
            jadval_nomi=log.jadval_nomi,
            yozuv_id=log.yozuv_id,
            amal=log.amal,
            eski_qiymat=log.eski_qiymat,
            yangi_qiymat=log.yangi_qiymat,
            sabab=log.sabab,
            vaqt=log.vaqt,
        )
        for log, ism in natijalar
    ]
    return Sahifalangan(items=items, jami=jami, sahifa=sahifa, sahifa_hajmi=sahifa_hajmi)

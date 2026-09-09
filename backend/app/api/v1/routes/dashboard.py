import json
from datetime import date, datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import rollarga_ruxsat
from app.api.v1.routes.agent import AGENT_HOLAT_KALITI
from app.core.config import settings
from app.core.database import get_db
from app.models.foydalanuvchi import Foydalanuvchi, Rol
from app.models.kip import HISOBLANADIGAN_HOLATLAR, Kip
from app.models.mahsulot import Mahsulot
from app.models.partiya import Partiya, PartiyaHolati
from app.models.shubhali_holat import ShubhaliHolat, ShubhaliHolatStatusi
from app.models.sozlama import Sozlama
from app.schemas.dashboard import AgentHolatJavob, DashboardJavob
from app.schemas.statistika import MahsulotJamlanmasi, SmenaJamlanmasi
from app.services.davr import davr_oraligi

router = APIRouter(prefix="/dashboard", tags=["dashboard"])

DAVRLAR = ("kunlik", "haftalik", "oylik", "mavsum")


def _agent_holatini_ol(db: Session) -> AgentHolatJavob | None:
    sozlama = db.get(Sozlama, AGENT_HOLAT_KALITI)
    if sozlama is None:
        return None
    try:
        qiymat = json.loads(sozlama.qiymat)
        yangilangan_vaqt = datetime.fromisoformat(qiymat["vaqt"])
    except (json.JSONDecodeError, KeyError, ValueError):
        return None

    eskirdimi = (datetime.now(timezone.utc) - yangilangan_vaqt).total_seconds() > settings.AGENT_HOLAT_ESKIRISH_SONIYA
    return AgentHolatJavob(
        ulangan=qiymat["ulangan"],
        oxirgi_xato=qiymat.get("oxirgi_xato"),
        anti_ogirlik_holati=qiymat["anti_ogirlik_holati"],
        navbat_uzunligi=qiymat["navbat_uzunligi"],
        yangilangan_vaqt=yangilangan_vaqt,
        yangimi=not eskirdimi,
    )


@router.get("", response_model=DashboardJavob)
def dashboard(
    davr: str = Query("kunlik"),
    db: Session = Depends(get_db),
    _: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.admin)),
) -> DashboardJavob:
    if davr not in DAVRLAR:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Noma'lum davr: {davr}. Ruxsat etilgan: {', '.join(DAVRLAR)}",
        )
    boshlanish, tugash = davr_oraligi(davr, date.today())

    qatorlar = db.execute(
        select(
            Mahsulot.kod,
            Mahsulot.nomi,
            func.count(Kip.id),
            func.coalesce(func.sum(Kip.ogirlik), 0),
        )
        .join(Partiya, Partiya.mahsulot_id == Mahsulot.id)
        .join(Kip, Kip.partiya_id == Partiya.id)
        .where(
            Kip.holati.in_(HISOBLANADIGAN_HOLATLAR),
            func.date(Kip.vaqt) >= boshlanish,
            func.date(Kip.vaqt) <= tugash,
        )
        .group_by(Mahsulot.kod, Mahsulot.nomi)
    ).all()
    mahsulotlar = [
        MahsulotJamlanmasi(mahsulot_kodi=kod, mahsulot_nomi=nomi, soni=soni, jami_kg=float(kg))
        for kod, nomi, soni, kg in qatorlar
    ]

    smena_qatorlari = db.execute(
        select(Kip.smena, func.count(Kip.id), func.coalesce(func.sum(Kip.ogirlik), 0))
        .where(
            Kip.holati.in_(HISOBLANADIGAN_HOLATLAR),
            func.date(Kip.vaqt) >= boshlanish,
            func.date(Kip.vaqt) <= tugash,
        )
        .group_by(Kip.smena)
        .order_by(Kip.smena)
    ).all()
    smenalar = [
        SmenaJamlanmasi(smena=smena.value, soni=soni, jami_kg=float(kg)) for smena, soni, kg in smena_qatorlari
    ]

    # Davrga bog'liq emas — doim joriy holatni ko'rsatadi
    ochiq_partiyalar_soni = db.scalar(
        select(func.count()).select_from(Partiya).where(Partiya.holati == PartiyaHolati.ochiq)
    ) or 0

    tasdiqlanmagan_soni = db.scalar(
        select(func.count()).select_from(ShubhaliHolat).where(ShubhaliHolat.holati == ShubhaliHolatStatusi.yangi)
    ) or 0

    return DashboardJavob(
        davr=davr,
        boshlanish_sanasi=boshlanish,
        tugash_sanasi=tugash,
        mahsulotlar=mahsulotlar,
        jami_soni=sum(m.soni for m in mahsulotlar),
        jami_kg=sum(m.jami_kg for m in mahsulotlar),
        smenalar=smenalar,
        ochiq_partiyalar_soni=ochiq_partiyalar_soni,
        tasdiqlanmagan_shubhali_holatlar_soni=tasdiqlanmagan_soni,
        agent_holati=_agent_holatini_ol(db),
    )

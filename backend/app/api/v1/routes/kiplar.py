from datetime import date, datetime, timezone

from fastapi import APIRouter, Body, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import rollarga_ruxsat
from app.core.config import settings
from app.core.database import get_db
from app.models.audit_log import AuditAmal, AuditLog
from app.models.foydalanuvchi import Foydalanuvchi, Rol
from app.models.kip import Kip, KipHolati
from app.models.mahsulot import Mahsulot
from app.models.partiya import Partiya, PartiyaHolati
from app.models.shubhali_holat import ShubhaliHolat, ShubhaliHolatStatusi
from app.schemas.hujjat import AuditLogJavob
from app.schemas.kip import KipBatafsilJavob, KipJavob, KipSinxronNatija, KipTahrirlash, KipYaratish
from app.schemas.smena import MahsulotBoyichaHolat, SmenaHolati

router = APIRouter(prefix="/kiplar", tags=["kiplar"])


def _keyingi_kip_raqami(db: Session, partiya_id: int) -> int:
    # Partiya qatorini qulflaymiz — bir vaqtda kelgan ikkita so'rov bir xil raqamni olmasligi uchun
    db.execute(select(Partiya.id).where(Partiya.id == partiya_id).with_for_update())
    oxirgi = db.scalar(select(func.max(Kip.kip_raqami)).where(Kip.partiya_id == partiya_id))
    return (oxirgi or 0) + 1


def _dublikat_topish(db: Session, partiya_id: int, ogirlik: float, hozir: datetime) -> Kip | None:
    songi = db.scalar(
        select(Kip)
        .where(Kip.partiya_id == partiya_id, Kip.holati == KipHolati.aktiv)
        .order_by(Kip.vaqt.desc())
        .limit(1)
    )
    if songi is None:
        return None
    if (hozir - songi.vaqt).total_seconds() > settings.DUPLIKAT_VAQT_OYNASI_SONIYA:
        return None
    if abs(float(songi.ogirlik) - ogirlik) > settings.DUPLIKAT_OGIRLIK_TOLERANSI_KG:
        return None
    return songi


def _bloklovchi_hodisa(db: Session, smena) -> ShubhaliHolat | None:
    return db.scalar(
        select(ShubhaliHolat)
        .where(ShubhaliHolat.holati == ShubhaliHolatStatusi.yangi, ShubhaliHolat.smena == smena)
        .order_by(ShubhaliHolat.vaqt.desc())
        .limit(1)
    )


@router.get("/smena/holati", response_model=SmenaHolati)
def smena_holati(
    db: Session = Depends(get_db),
    foydalanuvchi: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.operator)),
) -> SmenaHolati:
    bugun = date.today()
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
            Kip.smena == foydalanuvchi.smena,
            Kip.holati == KipHolati.aktiv,
            func.date(Kip.vaqt) == bugun,
        )
        .group_by(Mahsulot.kod, Mahsulot.nomi)
    ).all()

    mahsulotlar = [
        MahsulotBoyichaHolat(mahsulot_kodi=kod, mahsulot_nomi=nomi, soni=soni, jami_kg=float(jami_kg))
        for kod, nomi, soni, jami_kg in qatorlar
    ]
    return SmenaHolati(smena=foydalanuvchi.smena.value, sana=bugun.isoformat(), mahsulotlar=mahsulotlar)


@router.post("/sinxron", response_model=list[KipSinxronNatija])
def sinxronlash(
    malumotlar: list[KipYaratish],
    db: Session = Depends(get_db),
    foydalanuvchi: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.operator)),
) -> list[KipSinxronNatija]:
    """Offline navbatdan Stansiya Agenti tomonidan yuboriladi. Anti-o'g'irlik bloki
    va dublikat-ogohlantirish bu yerda TEKSHIRILMAYDI — bular allaqachon operator
    tomonidan (offline holatda) qaror qilingan haqiqiy amallar, faqat mijoz_id
    orqali texnik dublikatning oldi olinadi."""
    natijalar: list[KipSinxronNatija] = []

    for malumot in malumotlar:
        mavjud = db.scalar(select(Kip).where(Kip.mijoz_id == malumot.mijoz_id))
        if mavjud is not None:
            natijalar.append(KipSinxronNatija(mijoz_id=malumot.mijoz_id, holat="allaqachon_mavjud", kip_id=mavjud.id))
            continue

        partiya = db.get(Partiya, malumot.partiya_id)
        if partiya is None or partiya.holati != PartiyaHolati.ochiq:
            natijalar.append(
                KipSinxronNatija(mijoz_id=malumot.mijoz_id, holat="xato", xabar="Partiya topilmadi yoki ochiq emas")
            )
            continue

        kip = Kip(
            mijoz_id=malumot.mijoz_id,
            partiya_id=partiya.id,
            kip_raqami=_keyingi_kip_raqami(db, partiya.id),
            ogirlik=malumot.ogirlik,
            smena=foydalanuvchi.smena,
            operator_id=foydalanuvchi.id,
            mahalliy_vaqt=malumot.mahalliy_vaqt,
            surat_yoli=malumot.surat_yoli,
            stansiya_id=malumot.stansiya_id,
        )
        db.add(kip)
        db.flush()
        natijalar.append(KipSinxronNatija(mijoz_id=malumot.mijoz_id, holat="saqlandi", kip_id=kip.id))

    db.commit()
    return natijalar


@router.post("", response_model=KipJavob, status_code=status.HTTP_201_CREATED)
def saqlash(
    malumot: KipYaratish,
    db: Session = Depends(get_db),
    foydalanuvchi: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.operator)),
) -> Kip:
    mavjud = db.scalar(select(Kip).where(Kip.mijoz_id == malumot.mijoz_id))
    if mavjud is not None:
        return mavjud

    partiya = db.get(Partiya, malumot.partiya_id)
    if partiya is None or partiya.holati != PartiyaHolati.ochiq:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Partiya topilmadi yoki ochiq emas")

    bloklovchi = _bloklovchi_hodisa(db, foydalanuvchi.smena)
    if bloklovchi is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Tasdiqlanmagan 'yuk saqlanmadi' ogohlantirishi bor — avval uni tasdiqlang",
        )

    hozir = datetime.now(timezone.utc)
    if not malumot.majburiy:
        dublikat = _dublikat_topish(db, partiya.id, malumot.ogirlik, hozir)
        if dublikat is not None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={
                    "xabar": "Shunga o'xshash og'irlikdagi kip bir necha soniya oldin saqlangan. Bu haqiqatan ham yangi kipmi?",
                    "avvalgi_kip_id": dublikat.id,
                    "avvalgi_ogirlik": float(dublikat.ogirlik),
                    "avvalgi_vaqt": dublikat.vaqt.isoformat(),
                },
            )

    kip = Kip(
        mijoz_id=malumot.mijoz_id,
        partiya_id=partiya.id,
        kip_raqami=_keyingi_kip_raqami(db, partiya.id),
        ogirlik=malumot.ogirlik,
        smena=foydalanuvchi.smena,
        operator_id=foydalanuvchi.id,
        mahalliy_vaqt=malumot.mahalliy_vaqt,
        surat_yoli=malumot.surat_yoli,
        stansiya_id=malumot.stansiya_id,
    )
    db.add(kip)
    db.commit()
    db.refresh(kip)
    return kip


@router.get("/{kip_id}", response_model=KipBatafsilJavob)
def batafsil(
    kip_id: int,
    db: Session = Depends(get_db),
    foydalanuvchi: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.admin, Rol.tayyor_mahsulotlar, Rol.operator)),
) -> KipBatafsilJavob:
    natija = db.execute(
        select(Kip, Partiya.partiya_raqami, Mahsulot.kod, Mahsulot.nomi, Foydalanuvchi.ism)
        .join(Partiya, Kip.partiya_id == Partiya.id)
        .join(Mahsulot, Partiya.mahsulot_id == Mahsulot.id)
        .join(Foydalanuvchi, Kip.operator_id == Foydalanuvchi.id)
        .where(Kip.id == kip_id)
    ).first()
    if natija is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Kip topilmadi")

    kip, partiya_raqami, mahsulot_kodi, mahsulot_nomi, operator_ism = natija

    if foydalanuvchi.rol == Rol.operator and kip.smena != foydalanuvchi.smena:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="Faqat o'z smenangizdagi kipni ko'rishingiz mumkin"
        )

    audit_qatorlari = db.execute(
        select(AuditLog, Foydalanuvchi.ism)
        .join(Foydalanuvchi, AuditLog.foydalanuvchi_id == Foydalanuvchi.id)
        .where(AuditLog.jadval_nomi == "kiplar", AuditLog.yozuv_id == kip_id)
        .order_by(AuditLog.vaqt.desc())
    ).all()
    audit_log = [
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
        for log, ism in audit_qatorlari
    ]

    return KipBatafsilJavob(
        id=kip.id,
        mijoz_id=kip.mijoz_id,
        partiya_id=kip.partiya_id,
        partiya_raqami=partiya_raqami,
        mahsulot_kodi=mahsulot_kodi,
        mahsulot_nomi=mahsulot_nomi,
        kip_raqami=kip.kip_raqami,
        ogirlik=float(kip.ogirlik),
        smena=kip.smena,
        operator_id=kip.operator_id,
        operator_ism=operator_ism,
        mahalliy_vaqt=kip.mahalliy_vaqt,
        vaqt=kip.vaqt,
        sinxronlangan=kip.sinxronlangan,
        surat_yoli=kip.surat_yoli,
        holati=kip.holati,
        stansiya_id=kip.stansiya_id,
        audit_log=audit_log,
    )


@router.post("/{kip_id}/bekor-qilish", response_model=KipJavob)
def tezkor_bekor_qilish(
    kip_id: int,
    db: Session = Depends(get_db),
    foydalanuvchi: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.operator)),
) -> Kip:
    kip = db.get(Kip, kip_id)
    if kip is None or kip.holati != KipHolati.aktiv:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Kip topilmadi")
    if kip.smena != foydalanuvchi.smena:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Faqat shu smena o'z yozuvini bekor qila oladi")

    hozir = datetime.now(timezone.utc)
    if (hozir - kip.vaqt).total_seconds() > settings.BEKOR_QILISH_MUDDATI_SONIYA:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"{settings.BEKOR_QILISH_MUDDATI_SONIYA} soniyadan o'tgan — endi faqat Admin sababi bilan o'chira oladi",
        )

    kip.holati = KipHolati.bekor_qilingan
    db.add(
        AuditLog(
            foydalanuvchi_id=foydalanuvchi.id,
            jadval_nomi="kiplar",
            yozuv_id=kip.id,
            amal=AuditAmal.ochirildi,
            sabab=f"Tezkor bekor qilish ({settings.BEKOR_QILISH_MUDDATI_SONIYA}s ichida, sababsiz)",
        )
    )
    db.commit()
    db.refresh(kip)
    return kip


@router.patch("/{kip_id}", response_model=KipJavob)
def tahrirlash(
    kip_id: int,
    malumot: KipTahrirlash,
    db: Session = Depends(get_db),
    foydalanuvchi: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.admin)),
) -> Kip:
    kip = db.get(Kip, kip_id)
    if kip is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Kip topilmadi")

    eski_partiya = db.get(Partiya, kip.partiya_id)
    eski_mahsulot = db.get(Mahsulot, eski_partiya.mahsulot_id)
    eski_qiymat = {
        "ogirlik": float(kip.ogirlik),
        "holati": kip.holati.value,
        "mahsulot_kodi": eski_mahsulot.kod,
        "partiya_raqami": eski_partiya.partiya_raqami,
    }

    if malumot.ogirlik is not None:
        kip.ogirlik = malumot.ogirlik

    if malumot.mahsulot_kodi is not None or malumot.partiya_raqami is not None:
        if malumot.mahsulot_kodi is None or malumot.partiya_raqami is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Mahsulot va partiya raqami birga ko'rsatilishi kerak",
            )
        yangi_mahsulot = db.scalar(select(Mahsulot).where(Mahsulot.kod == malumot.mahsulot_kodi))
        if yangi_mahsulot is None:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Mahsulot topilmadi")
        yangi_partiya = db.scalar(
            select(Partiya).where(
                Partiya.mahsulot_id == yangi_mahsulot.id,
                Partiya.partiya_raqami == malumot.partiya_raqami,
            )
        )
        if yangi_partiya is None:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Partiya topilmadi")
        kip.partiya_id = yangi_partiya.id

    kip.holati = KipHolati.tahrirlangan

    joriy_partiya = db.get(Partiya, kip.partiya_id)
    joriy_mahsulot = db.get(Mahsulot, joriy_partiya.mahsulot_id)
    yangi_qiymat = {
        "ogirlik": float(kip.ogirlik),
        "holati": kip.holati.value,
        "mahsulot_kodi": joriy_mahsulot.kod,
        "partiya_raqami": joriy_partiya.partiya_raqami,
    }

    db.add(
        AuditLog(
            foydalanuvchi_id=foydalanuvchi.id,
            jadval_nomi="kiplar",
            yozuv_id=kip.id,
            amal=AuditAmal.tahrirlandi,
            eski_qiymat=eski_qiymat,
            yangi_qiymat=yangi_qiymat,
            sabab=malumot.sabab,
        )
    )
    db.commit()
    db.refresh(kip)
    return kip


@router.delete("/{kip_id}", response_model=KipJavob)
def ochirish(
    kip_id: int,
    sabab: str = Body(..., embed=True),
    db: Session = Depends(get_db),
    foydalanuvchi: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.admin)),
) -> Kip:
    kip = db.get(Kip, kip_id)
    if kip is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Kip topilmadi")

    kip.holati = KipHolati.bekor_qilingan
    db.add(
        AuditLog(
            foydalanuvchi_id=foydalanuvchi.id,
            jadval_nomi="kiplar",
            yozuv_id=kip.id,
            amal=AuditAmal.ochirildi,
            eski_qiymat={"holati": "aktiv"},
            yangi_qiymat={"holati": "bekor_qilingan"},
            sabab=sabab,
        )
    )
    db.commit()
    db.refresh(kip)
    return kip

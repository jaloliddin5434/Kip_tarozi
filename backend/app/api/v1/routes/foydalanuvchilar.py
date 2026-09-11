from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import rollarga_ruxsat
from app.core.database import get_db
from app.core.security import parolni_hash
from app.models.audit_log import AuditAmal, AuditLog
from app.models.foydalanuvchi import Foydalanuvchi, Rol
from app.schemas.foydalanuvchi import FoydalanuvchiJavob, FoydalanuvchiTahrirlash, FoydalanuvchiTokenBekorQilish

router = APIRouter(prefix="/foydalanuvchilar", tags=["foydalanuvchilar"])

LOGIN_MIN_UZUNLIK = 3
PAROL_MIN_UZUNLIK = 4


@router.get("", response_model=list[FoydalanuvchiJavob])
def royxat(
    db: Session = Depends(get_db),
    _: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.admin)),
) -> list[Foydalanuvchi]:
    """Barcha hisoblar (Admin, Operator A/B/C/D, Tayyor mahsulotlar bo'limi) —
    faqat Admin ko'ra oladi."""
    return list(
        db.scalars(
            select(Foydalanuvchi).order_by(Foydalanuvchi.rol, Foydalanuvchi.smena, Foydalanuvchi.login)
        )
    )


@router.patch("/{foydalanuvchi_id}", response_model=FoydalanuvchiJavob)
def tahrirlash(
    foydalanuvchi_id: int,
    malumot: FoydalanuvchiTahrirlash,
    db: Session = Depends(get_db),
    admin: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.admin)),
) -> Foydalanuvchi:
    """Hisobning login va/yoki parolini o'zgartiradi (Admin-only). Kamida
    bittasi berilishi kerak. Amal audit_log'ga yoziladi — lekin PAROLNING
    O'ZI hech qachon log'ga tushmaydi, faqat "parol o'zgartirildi" belgisi."""
    if malumot.login is None and malumot.parol is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Kamida login yoki parol berilishi kerak",
        )

    nishon = db.get(Foydalanuvchi, foydalanuvchi_id)
    if nishon is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Foydalanuvchi topilmadi")

    eski_qiymat: dict = {}
    yangi_qiymat: dict = {}

    if malumot.login is not None and malumot.login != nishon.login:
        if len(malumot.login) < LOGIN_MIN_UZUNLIK:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Login kamida {LOGIN_MIN_UZUNLIK} belgidan iborat bo'lishi kerak",
            )
        band = db.scalar(
            select(Foydalanuvchi).where(
                Foydalanuvchi.login == malumot.login,
                Foydalanuvchi.id != nishon.id,
            )
        )
        if band is not None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"'{malumot.login}' login boshqa hisobda band",
            )
        eski_qiymat["login"] = nishon.login
        yangi_qiymat["login"] = malumot.login
        nishon.login = malumot.login

    if malumot.parol is not None:
        if len(malumot.parol) < PAROL_MIN_UZUNLIK:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Parol kamida {PAROL_MIN_UZUNLIK} belgidan iborat bo'lishi kerak",
            )
        nishon.parol_hash = parolni_hash(malumot.parol)
        # Parolning O'ZI emas — faqat o'zgargani belgilanadi
        eski_qiymat["parol"] = "***"
        yangi_qiymat["parol"] = "o'zgartirildi"
        # Parol o'zgarganda BARCHA eski tokenlar darhol bekor bo'lishi kerak
        # (audit topilmasi: aks holda o'g'irlangan/eski token cheksiz
        # ishlashda davom etardi) — token_versiyasi oshirilishi
        # `app/api/deps.py:joriy_foydalanuvchi()` orqali tekshiriladi.
        nishon.token_versiyasi += 1
        eski_qiymat["token_versiyasi"] = nishon.token_versiyasi - 1
        yangi_qiymat["token_versiyasi"] = nishon.token_versiyasi

    if not yangi_qiymat:
        # login berilgan, lekin mavjudi bilan bir xil — o'zgarish yo'q
        return nishon

    # Login yoki parol o'zgarganda xavfsizlik uchun xato-urinish hisoblagichi
    # va blokni tozalaymiz. ESLATMA: faqat LOGIN o'zgarganda (parolsiz) eski
    # tokenlar hali ham amal qiladi — token_versiyasi FAQAT parol
    # o'zgarganda oshiriladi (yuqoriga qarang); login o'zgarishi shu
    # foydalanuvchining boshqa hech qanday maxfiy ma'lumotini oshkor
    # qilmagani uchun sessiyani darhol bekor qilish shart emas.
    nishon.xato_urinishlar = 0
    nishon.bloklangan_gacha = None

    ozini_ozgartirdi = nishon.id == admin.id
    sabab = "Admin hisobning login/parolini o'zgartirdi"
    if ozini_ozgartirdi:
        sabab += " (o'z hisobi)"

    db.add(
        AuditLog(
            foydalanuvchi_id=admin.id,
            jadval_nomi="foydalanuvchilar",
            yozuv_id=nishon.id,
            amal=AuditAmal.tahrirlandi,
            eski_qiymat=eski_qiymat or None,
            yangi_qiymat=yangi_qiymat,
            sabab=sabab,
        )
    )
    db.commit()
    db.refresh(nishon)
    return nishon


@router.post("/{foydalanuvchi_id}/tokenlarni-bekor-qilish", response_model=FoydalanuvchiJavob)
def tokenlarni_bekor_qilish(
    foydalanuvchi_id: int,
    malumot: FoydalanuvchiTokenBekorQilish | None = None,
    db: Session = Depends(get_db),
    admin: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.admin)),
) -> Foydalanuvchi:
    """Favqulodda holat uchun (masalan operator kompyuteri o'g'irlangan yoki
    yo'qolgan) — PAROLNI O'ZGARTIRMASDAN, shu hisobning BARCHA amaldagi
    (muddati hali tugamagan) tokenlarini darhol bekor qiladi
    (`token_versiyasi` oshiriladi). Foydalanuvchi keyingi so'rovda 401 oladi
    va qaytadan login qilishi kerak bo'ladi."""
    nishon = db.get(Foydalanuvchi, foydalanuvchi_id)
    if nishon is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Foydalanuvchi topilmadi")

    eski_versiya = nishon.token_versiyasi
    nishon.token_versiyasi += 1

    sabab = (malumot.sabab.strip() if malumot and malumot.sabab and malumot.sabab.strip() else None) or (
        "Admin barcha tokenlarni bekor qildi (favqulodda holat, parol o'zgartirilmadi)"
    )
    if nishon.id == admin.id:
        sabab += " (o'z hisobi)"

    db.add(
        AuditLog(
            foydalanuvchi_id=admin.id,
            jadval_nomi="foydalanuvchilar",
            yozuv_id=nishon.id,
            amal=AuditAmal.tahrirlandi,
            eski_qiymat={"token_versiyasi": eski_versiya},
            yangi_qiymat={"token_versiyasi": nishon.token_versiyasi},
            sabab=sabab,
        )
    )
    db.commit()
    db.refresh(nishon)
    return nishon

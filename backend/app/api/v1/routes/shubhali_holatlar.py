import uuid
from datetime import date, datetime, timezone

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import agent_autentifikatsiya, rollarga_ruxsat
from app.core.database import get_db
from app.models.foydalanuvchi import Foydalanuvchi, Rol, Smena
from app.models.kip import Kip
from app.models.mahsulot import Mahsulot
from app.models.partiya import Partiya, PartiyaHolati
from app.models.shubhali_holat import ShubhaliHolat, ShubhaliHolatStatusi
from app.schemas.kip import KipJavob
from app.schemas.sahifalash import Sahifalangan
from app.schemas.shubhali_holat import (
    ShubhaliHolatJavob,
    ShubhaliHolatKipSifatidaSaqlash,
    ShubhaliHolatRoyxatJavob,
    ShubhaliHolatStatistika,
    ShubhaliOperatorSoni,
)
from app.services.davr import sargable_pastki, sargable_yuqori
from app.services.media import surat_ommaviy_url
from app.services.storage.rasm import rasm_saqla
from app.services.telegram import surat_yubor, xatolik_xabari

router = APIRouter(prefix="/shubhali-holatlar", tags=["shubhali-holatlar"])


@router.post("", response_model=ShubhaliHolatJavob, status_code=status.HTTP_201_CREATED)
async def hodisa_royxatga_ol(
    ogirlik: float = Form(...),
    vaqt: datetime = Form(...),
    smena: str | None = Form(None),
    mahsulot_kodi: str | None = Form(None),
    stansiya_id: int | None = Form(None),
    surat: UploadFile | None = File(None),
    db: Session = Depends(get_db),
    _: None = Depends(agent_autentifikatsiya),
) -> ShubhaliHolat:
    """Stansiya Agenti anti-o'g'irlik state machine'i 'yuk saqlanmadi' hodisasini
    aniqlaganda shu endpointga murojaat qiladi (foydalanuvchi tokeni bilan emas,
    doimiy AGENT_API_KEY bilan — chunki bu operator amalidan mustaqil, avtomatik amal)."""

    smena_enum = Smena(smena) if smena else None

    surat_yoli = None
    if surat is not None:
        baytlar = await surat.read()
        # Shubhali holat surati mahsulot papkasidan tashqarida — Smena_<X>/shubhali_holatlar/
        surat_yoli = rasm_saqla(baytlar, smena=smena or "umumiy", vaqt=vaqt, turi="shubha")

    hodisa = ShubhaliHolat(vaqt=vaqt, smena=smena_enum, ogirlik=ogirlik, surat_yoli=surat_yoli, stansiya_id=stansiya_id)
    db.add(hodisa)
    db.commit()
    db.refresh(hodisa)

    smena_matni = smena or "noma'lum"
    xatolik_xabari(db, f"⚠️ YUK SAQLANMADI!\nSmena: {smena_matni}\nOg'irlik: {ogirlik} kg\nVaqt: {vaqt.isoformat()}")
    return hodisa


@router.get("", response_model=Sahifalangan[ShubhaliHolatRoyxatJavob])
def royxat(
    sana_dan: date | None = Query(None),
    sana_gacha: date | None = Query(None),
    smena: Smena | None = Query(None),
    operator_id: int | None = Query(None),
    tasdiqlangan: bool | None = Query(None),
    sahifa: int = Query(1, ge=1),
    sahifa_hajmi: int = Query(50, ge=1, le=500),
    db: Session = Depends(get_db),
    _: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.admin)),
) -> Sahifalangan[ShubhaliHolatRoyxatJavob]:
    """Admin panel — barcha 'yuk saqlanmadi' hodisalari, filtr bilan. Smena/vaqt
    bo'yicha statistika shu ro'yxatni filtrlash orqali olinadi (masalan
    smena=A bilan filtrlab, `jami` maydonidan shu smenadagi hodisalar sonini
    ko'rish mumkin)."""
    korib_chiqqan = Foydalanuvchi.__table__.alias("korib_chiqqan")
    operator = Foydalanuvchi.__table__.alias("operator")

    sorov = (
        select(ShubhaliHolat, korib_chiqqan.c.ism, operator.c.ism)
        .outerjoin(korib_chiqqan, ShubhaliHolat.korib_chiqqan_id == korib_chiqqan.c.id)
        .outerjoin(operator, ShubhaliHolat.operator_id == operator.c.id)
    )
    if sana_dan is not None:
        sorov = sorov.where(ShubhaliHolat.vaqt >= sargable_pastki(sana_dan))
    if sana_gacha is not None:
        sorov = sorov.where(ShubhaliHolat.vaqt < sargable_yuqori(sana_gacha))
    if smena is not None:
        sorov = sorov.where(ShubhaliHolat.smena == smena)
    if operator_id is not None:
        sorov = sorov.where(ShubhaliHolat.operator_id == operator_id)
    if tasdiqlangan is not None:
        holati_qiymati = ShubhaliHolatStatusi.korib_chiqildi if tasdiqlangan else ShubhaliHolatStatusi.yangi
        sorov = sorov.where(ShubhaliHolat.holati == holati_qiymati)

    jami = db.scalar(select(func.count()).select_from(sorov.subquery())) or 0

    sahifalangan_sorov = (
        sorov.order_by(ShubhaliHolat.vaqt.desc(), ShubhaliHolat.id.desc())
        .offset((sahifa - 1) * sahifa_hajmi)
        .limit(sahifa_hajmi)
    )
    natijalar = db.execute(sahifalangan_sorov).all()

    items = [
        ShubhaliHolatRoyxatJavob(
            id=hodisa.id,
            vaqt=hodisa.vaqt,
            smena=hodisa.smena,
            ogirlik=float(hodisa.ogirlik),
            surat_yoli=hodisa.surat_yoli,
            holati=hodisa.holati,
            tasdiqlangan=hodisa.holati == ShubhaliHolatStatusi.korib_chiqildi,
            korib_chiqqan_id=hodisa.korib_chiqqan_id,
            korib_chiqilgan_vaqt=hodisa.korib_chiqilgan_vaqt,
            stansiya_id=hodisa.stansiya_id,
            korib_chiqqan_ism=korib_chiqqan_ism,
            operator_ism=operator_ism,
        )
        for hodisa, korib_chiqqan_ism, operator_ism in natijalar
    ]
    return Sahifalangan(items=items, jami=jami, sahifa=sahifa, sahifa_hajmi=sahifa_hajmi)


@router.get("/statistika", response_model=ShubhaliHolatStatistika)
def statistika(
    sana_dan: date | None = Query(None),
    sana_gacha: date | None = Query(None),
    db: Session = Depends(get_db),
    _: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.admin)),
) -> ShubhaliHolatStatistika:
    """Qaysi smenada/operatorda 'yuk saqlanmadi' hodisasi ko'proq uchrayotganini
    ko'rsatadi. Faqat operator 'Tushundim' bosib tasdiqlagan (haqiqatan yuz bergan)
    hodisalar hisoblanadi — hali ko'rib chiqilmagan (kutilayotgan) holatlar
    statistikaga kirmaydi."""
    shartlar = [ShubhaliHolat.holati == ShubhaliHolatStatusi.korib_chiqildi]
    if sana_dan is not None:
        shartlar.append(ShubhaliHolat.vaqt >= sargable_pastki(sana_dan))
    if sana_gacha is not None:
        shartlar.append(ShubhaliHolat.vaqt < sargable_yuqori(sana_gacha))

    smena_soni = {smena.value: 0 for smena in Smena}
    smena_qatorlari = db.execute(
        select(ShubhaliHolat.smena, func.count(ShubhaliHolat.id)).where(*shartlar).group_by(ShubhaliHolat.smena)
    ).all()
    for smena, soni in smena_qatorlari:
        if smena is not None:
            smena_soni[smena.value] = soni

    operator_qatorlari = db.execute(
        select(Foydalanuvchi.id, Foydalanuvchi.ism, func.count(ShubhaliHolat.id))
        .join(Foydalanuvchi, ShubhaliHolat.operator_id == Foydalanuvchi.id)
        .where(*shartlar)
        .group_by(Foydalanuvchi.id, Foydalanuvchi.ism)
        .order_by(func.count(ShubhaliHolat.id).desc())
    ).all()

    return ShubhaliHolatStatistika(
        smena_boyicha=smena_soni,
        operator_boyicha=[
            ShubhaliOperatorSoni(operator_id=op_id, ism=ism, soni=soni) for op_id, ism, soni in operator_qatorlari
        ],
    )


@router.patch("/{hodisa_id}/tasdiqla", response_model=ShubhaliHolatJavob)
def tasdiqlash(
    hodisa_id: int,
    db: Session = Depends(get_db),
    foydalanuvchi: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.operator, Rol.admin)),
) -> ShubhaliHolat:
    """"Ko'rdim" — hodisani SOXTA SIGNAL sifatida ko'rib chiqib yopadi, HECH
    QANDAY Kip yaratilmaydi (haqiqiy Kip yaratish uchun qarang
    `kip_sifatida_saqlash()` — `POST /{id}/saqlash`). Operator ilgari o'zini
    bloklashdan chiqarish uchun ham shu endpointni chaqirar edi (AUDIT
    TUZATISHI: operator endi umuman bloklanmaydi — bu chaqiruv frontendda
    olib tashlandi), shuning uchun endi FAQAT admin panelidan ("Ko'rdim"
    tugmasi) chaqiriladi — lekin operatorga ruxsat ATAYLAB olib
    tashlanmadi (zararsiz, orqaga-mos)."""
    hodisa = db.get(ShubhaliHolat, hodisa_id)
    if hodisa is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Hodisa topilmadi")

    hodisa.holati = ShubhaliHolatStatusi.korib_chiqildi
    hodisa.korib_chiqqan_id = foydalanuvchi.id
    hodisa.korib_chiqilgan_vaqt = datetime.now(timezone.utc)
    db.commit()
    db.refresh(hodisa)
    return hodisa


@router.post("/{hodisa_id}/saqlash", response_model=KipJavob)
def kip_sifatida_saqlash(
    hodisa_id: int,
    malumot: ShubhaliHolatKipSifatidaSaqlash,
    db: Session = Depends(get_db),
    foydalanuvchi: Foydalanuvchi = Depends(rollarga_ruxsat(Rol.admin)),
) -> KipJavob:
    """Admin hodisani ("yuk saqlanmadi") HAQIQIY bo'lgan deb hisoblab, o'sha
    og'irlik bilan qo'lda mahsulot/partiya tanlab, HAQIQIY Kip yozuvi
    yaratadi va hodisani "ko'rib chiqildi" deb belgilaydi. Idempotent emas —
    hodisa allaqachon ko'rib chiqilgan bo'lsa 409 (bitta hodisadan ikkita
    Kip yaratilib qolmasligi uchun)."""
    hodisa = db.execute(
        select(ShubhaliHolat).where(ShubhaliHolat.id == hodisa_id).with_for_update()
    ).scalar_one_or_none()
    if hodisa is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Hodisa topilmadi")
    if hodisa.holati != ShubhaliHolatStatusi.yangi:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Hodisa allaqachon ko'rib chiqilgan")
    if hodisa.smena is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Bu hodisada smena aniqlanmagan — Kip sifatida saqlab bo'lmaydi",
        )

    mahsulot = db.scalar(select(Mahsulot).where(Mahsulot.kod == malumot.mahsulot_kodi))
    if mahsulot is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Mahsulot topilmadi")
    partiya = db.scalar(
        select(Partiya).where(
            Partiya.mahsulot_id == mahsulot.id,
            Partiya.partiya_raqami == malumot.partiya_raqami,
        )
    )
    if partiya is None or partiya.holati != PartiyaHolati.ochiq:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Partiya topilmadi yoki ochiq emas")

    # Partiya qatorini qulflaymiz — kiplar.py:_keyingi_kip_raqami() bilan bir
    # xil naqsh (bir vaqtda kelgan ikkita so'rov bir xil raqamni olmasligi uchun).
    db.execute(select(Partiya.id).where(Partiya.id == partiya.id).with_for_update())
    oxirgi_raqam = db.scalar(select(func.max(Kip.kip_raqami)).where(Kip.partiya_id == partiya.id))

    kip = Kip(
        mijoz_id=str(uuid.uuid4()),
        partiya_id=partiya.id,
        kip_raqami=(oxirgi_raqam or 0) + 1,
        ogirlik=hodisa.ogirlik,
        smena=hodisa.smena,
        # Hodisada operator_id deyarli har doim yo'q (Stansiya Agenti buni
        # bilmaydi) — bunday holda buni QO'LDA HAL QILAYOTGAN adminning o'zi
        # sifatida yozamiz (soxta/noma'lum operator o'rniga).
        operator_id=hodisa.operator_id or foydalanuvchi.id,
        mahalliy_vaqt=hodisa.vaqt,
        surat_yoli=hodisa.surat_yoli,
        stansiya_id=hodisa.stansiya_id,
    )
    db.add(kip)

    hodisa.holati = ShubhaliHolatStatusi.korib_chiqildi
    hodisa.korib_chiqqan_id = foydalanuvchi.id
    hodisa.korib_chiqilgan_vaqt = datetime.now(timezone.utc)
    db.commit()
    db.refresh(kip)

    # Surat mavjud bo'lsa — kiplar.py:saqlash() bilan bir xil naqsh: alohida
    # "surat boti"ga yuboriladi. Xato bo'lsa ham operatorni/adminni bloklamaydi.
    xabar_id = surat_yubor(db, kip.surat_yoli, mahsulot.nomi, partiya.partiya_raqami, kip.kip_raqami, kip.ogirlik)
    if xabar_id is not None:
        kip.telegram_surat_xabar_id = xabar_id
        db.commit()
        db.refresh(kip)

    javob = KipJavob.model_validate(kip)
    javob.surat_yoli = surat_ommaviy_url(kip.surat_yoli)
    return javob

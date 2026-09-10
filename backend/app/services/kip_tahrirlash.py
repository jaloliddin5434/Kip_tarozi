"""Kipning og'irligi/mahsuloti-partiyasini tahrirlash — umumiy mantiq.

`PATCH /kiplar/{id}` (admin panel) HAM, kip to'g'rilash zayavkasi
tasdiqlangandagi oqim HAM shu yerdagi `kipni_tahrir_qil()`ni chaqiradi —
ikkalasida ham bir xil natija: og'irlik yangilanadi, mahsulot/partiya
o'zgarsa surat (agar mavjud bo'lsa) TO'G'RI yangi papkaga ko'chadi, va
AuditLog yoziladi.
"""

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models.audit_log import AuditAmal, AuditLog
from app.models.kip import Kip, KipHolati
from app.models.mahsulot import Mahsulot
from app.models.partiya import Partiya
from app.services.storage.rasm import rasm_kochir
from app.services.telegram import surat_xabarini_yangila


def _keyingi_kip_raqami(db: Session, partiya_id: int) -> int:
    # Partiya qatorini qulflaymiz — bir vaqtda kelgan boshqa saqlash/ko'chirish
    # bir xil raqamni olmasin (kiplar.py/kamera_tasdiq.py'dagi bilan bir xil mantiq).
    db.execute(select(Partiya.id).where(Partiya.id == partiya_id).with_for_update())
    oxirgi = db.scalar(select(func.max(Kip.kip_raqami)).where(Kip.partiya_id == partiya_id))
    return (oxirgi or 0) + 1


def kipni_tahrir_qil(
    db: Session,
    kip: Kip,
    *,
    yangi_ogirlik: float | None,
    yangi_partiya: Partiya | None,
    sabab: str,
    foydalanuvchi_id: int,
) -> Kip:
    """`kip`ni joyida yangilaydi va `AuditLog` yozadi. `db.flush()` qiladi,
    COMMIT QILMAYDI — chaqiruvchi commit qiladi (bu loyihadagi service/
    funksiyalar naqshi, masalan `kamera_tasdiq.sorovni_hal_qil`).

    `yangi_partiya` berilsa va uning mahsuloti ESKISIDAN farq qilsa (partiya
    raqami o'zgarib, mahsulot bir xil qolsa — surat papkasi ham o'zgarmaydi,
    chunki u faqat mahsulot nomiga bog'liq) — mavjud surat (bo'lsa)
    `rasm_kochir()` bilan yangi mahsulot papkasiga ko'chiriladi.

    `kip_raqami` HAR DOIM (partiya_id, kip_raqami) juftligi bo'yicha o'ziga
    xos (`uq_kip_partiya_raqam`) — shuning uchun partiya haqiqatan o'zgarsa,
    eski kip_raqami yangi partiyada band bo'lishi mumkin (masalan ikkalasida
    ham "9"-kip bo'lsa) va bazaga yozishda IntegrityError berardi. Shu sabab
    partiya o'zgarganda kip YANGI partiyadagi navbatdagi bo'sh raqamni oladi."""
    eski_partiya = db.get(Partiya, kip.partiya_id)
    eski_mahsulot = db.get(Mahsulot, eski_partiya.mahsulot_id)
    eski_qiymat = {
        "ogirlik": float(kip.ogirlik),
        "holati": kip.holati.value,
        "mahsulot_kodi": eski_mahsulot.kod,
        "partiya_raqami": eski_partiya.partiya_raqami,
    }

    if yangi_ogirlik is not None:
        kip.ogirlik = yangi_ogirlik

    if yangi_partiya is not None and yangi_partiya.id != kip.partiya_id:
        yangi_mahsulot = db.get(Mahsulot, yangi_partiya.mahsulot_id)
        mahsulot_haqiqatan_ozgardi = yangi_mahsulot.id != eski_mahsulot.id
        if kip.surat_yoli and mahsulot_haqiqatan_ozgardi:
            kip.surat_yoli = rasm_kochir(
                kip.surat_yoli,
                smena=kip.smena.value,
                vaqt=kip.vaqt,
                yangi_mahsulot_nomi=yangi_mahsulot.nomi,
            )
        kip.kip_raqami = _keyingi_kip_raqami(db, yangi_partiya.id)
        kip.partiya_id = yangi_partiya.id

        # Mahsulot HAQIQATAN o'zgargan bo'lsa va shu kip uchun avval "surat
        # boti"ga xabar yuborilgan bo'lsa — o'sha ESKI xabarning caption'ini
        # yangi ma'lumot bilan yangilaymiz (operator/admin buni Telegramda
        # ham ko'rsin). Xato bo'lsa (masalan xabar juda eski) bloklamaydi.
        if mahsulot_haqiqatan_ozgardi and kip.telegram_surat_xabar_id:
            surat_xabarini_yangila(
                db,
                kip.telegram_surat_xabar_id,
                yangi_mahsulot.nomi,
                yangi_partiya.partiya_raqami,
                kip.kip_raqami,
                float(kip.ogirlik),
            )

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
            foydalanuvchi_id=foydalanuvchi_id,
            jadval_nomi="kiplar",
            yozuv_id=kip.id,
            amal=AuditAmal.tahrirlandi,
            eski_qiymat=eski_qiymat,
            yangi_qiymat=yangi_qiymat,
            sabab=sabab,
        )
    )
    db.flush()
    return kip

import logging
import shutil
from datetime import datetime
from pathlib import Path
from uuid import uuid4

from app.core.config import settings

logger = logging.getLogger("rasm")


def rasm_saqla(
    baytlar: bytes,
    smena: str,
    vaqt: datetime,
    turi: str,
    mahsulot_nomi: str | None = None,
) -> str:
    """Suratni STORAGE_PATH ostida quyidagi tuzilma bo'yicha saqlaydi:

        <Oy>/<Kun>/Smena_<A|B|C|D>/<Mahsulot nomi>/<fayl>.jpg          (turi="kip")
        <Oy>/<Kun>/Smena_<A|B|C|D>/shubhali_holatlar/<fayl>.jpg        (turi="shubha")

    Shubhali holatlarda mahsulot ko'pincha noma'lum bo'lgani uchun ular
    mahsulot papkasidan tashqarida, alohida "shubhali_holatlar" papkasida.
    Natijada STORAGE_PATH'ga nisbiy yo'l qaytariladi (bazaga shu saqlanadi)."""
    papka = (
        Path(settings.STORAGE_PATH)
        / vaqt.strftime("%Y-%m")
        / vaqt.strftime("%Y-%m-%d")
        / f"Smena_{smena}"
    )
    if turi == "shubha":
        papka = papka / "shubhali_holatlar"
    else:
        papka = papka / (mahsulot_nomi or "umumiy")
    papka.mkdir(parents=True, exist_ok=True)

    yoli = papka / f"{uuid4().hex}.jpg"
    yoli.write_bytes(baytlar)
    return str(yoli.relative_to(settings.STORAGE_PATH)).replace("\\", "/")


def rasm_kochir(eski_nisbiy_yol: str, *, smena: str, vaqt: datetime, yangi_mahsulot_nomi: str) -> str:
    """Mavjud kip suratini YANGI mahsulot papkasiga ko'chiradi — masalan admin
    kipning mahsulotini tahrirlaganda (`rasm_saqla` bilan bir xil formula,
    lekin fayl NOMI o'zgarmaydi, chunki bu yaratish emas, ko'chirish).

    Sana/smena kipning o'zi bilan birga kelgani uchun o'zgarmaydi — faqat
    mahsulot segmenti farq qiladi. Eski fayl diskda topilmasa (masalan qo'lda
    o'chirilgan bo'lsa) — ogohlantirish bilan log yoziladi va ESKI nisbiy yo'l
    o'zgarishsiz qaytariladi (tahrirlashning o'zi bloklanmasligi kerak)."""
    eski_yoli = Path(settings.STORAGE_PATH) / eski_nisbiy_yol
    if not eski_yoli.is_file():
        logger.warning("Kip surati ko'chirilmadi — fayl diskda topilmadi: %s", eski_yoli)
        return eski_nisbiy_yol

    yangi_papka = (
        Path(settings.STORAGE_PATH)
        / vaqt.strftime("%Y-%m")
        / vaqt.strftime("%Y-%m-%d")
        / f"Smena_{smena}"
        / yangi_mahsulot_nomi
    )
    yangi_papka.mkdir(parents=True, exist_ok=True)
    yangi_yoli = yangi_papka / eski_yoli.name
    shutil.move(str(eski_yoli), str(yangi_yoli))
    logger.info("Kip surati ko'chirildi: %s -> %s", eski_yoli, yangi_yoli)
    return str(yangi_yoli.relative_to(settings.STORAGE_PATH)).replace("\\", "/")

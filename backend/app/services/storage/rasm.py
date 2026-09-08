from datetime import datetime
from pathlib import Path
from uuid import uuid4

from app.core.config import settings


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

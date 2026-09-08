"""Saqlangan fayllar (kip surati, shubhali holat surati) uchun ommaviy URL.

Fayllar diskda STORAGE_PATH ostida saqlanadi va bazaga STORAGE_PATH'ga nisbatan
yo'l yoziladi (rasm_saqla qaytaradi). Frontend rasmni Image.network orqali
ochgani uchun, unga to'liq URL kerak — main.py'da StaticFiles `/media` ga
STORAGE_PATH mount qilingan.
"""

from app.core.config import settings


def surat_ommaviy_url(nisbiy_yol: str | None) -> str | None:
    """Bazadagi nisbiy yo'lni frontend ochib oladigan to'liq URLga aylantiradi.
    None yoki bo'sh bo'lsa — o'zi qaytariladi; allaqachon absolyut (http...) bo'lsa
    ham tegilmaydi (offline navbatdan kelgan yozuvlar bilan mos)."""
    if not nisbiy_yol:
        return nisbiy_yol
    if nisbiy_yol.startswith(("http://", "https://")):
        return nisbiy_yol
    return f"{settings.BACKEND_URL.rstrip('/')}/media/{nisbiy_yol.lstrip('/')}"

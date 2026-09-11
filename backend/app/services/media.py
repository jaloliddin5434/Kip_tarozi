"""Saqlangan fayllar (kip surati, shubhali holat surati) uchun ommaviy URL.

Fayllar diskda STORAGE_PATH ostida saqlanadi va bazaga STORAGE_PATH'ga nisbatan
yo'l yoziladi (rasm_saqla qaytaradi). Frontend rasmni Image.network orqali
ochadi — URL `app/api/v1/routes/media.py`dagi AUTENTIFIKATSIYALANGAN
`/media/kip-surat/{fayl_yoli}` endpointiga ishora qiladi (JWT talab qiladi;
audit topilmasidan keyin `StaticFiles` orqali ochiq mount olib tashlandi).
"""

from app.core.config import settings


def surat_ommaviy_url(nisbiy_yol: str | None) -> str | None:
    """Bazadagi nisbiy yo'lni frontend ochib oladigan to'liq URLga aylantiradi.
    None yoki bo'sh bo'lsa — o'zi qaytariladi; allaqachon absolyut (http...) bo'lsa
    ham tegilmaydi (offline navbatdan kelgan yozuvlar bilan mos). Natija URL
    autentifikatsiya talab qiladi — frontend `Authorization: Bearer` header
    bilan so'rashi kerak (oddiy `<img src>` emas)."""
    if not nisbiy_yol:
        return nisbiy_yol
    if nisbiy_yol.startswith(("http://", "https://")):
        return nisbiy_yol
    return f"{settings.BACKEND_URL.rstrip('/')}/media/kip-surat/{nisbiy_yol.lstrip('/')}"

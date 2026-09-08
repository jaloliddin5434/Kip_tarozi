"""IP kamera integratsiyasi — kip saqlanganda bitta surat olish.

Kamera: Hikvision IPC-B140HA (va ISAPI mos boshqa kameralar). Bitta JPEG kadr
ISAPI snapshot endpointidan Digest autentifikatsiya bilan olinadi:

    GET http://<KAMERA_IP>/ISAPI/Streaming/channels/101/picture

Barcha xatolar shu modul ichida yutiladi — chaqiruvchi hech qачон istisno
ko'rmaydi (kamera ishlamasa ham operator bloklanmasligi kerak).
"""

import logging
from datetime import datetime

import httpx

from app.core.config import settings
from app.services.storage.rasm import rasm_saqla

logger = logging.getLogger("kamera")


def sozlangan() -> bool:
    """Kamera integratsiyasi ishlashi uchun IP, login va parol — uchalasi kerak."""
    return bool(settings.KAMERA_IP and settings.KAMERA_LOGIN and settings.KAMERA_PAROL)


def snapshot_ol() -> bytes | None:
    """Kameradan bitta JPEG kadr oladi. Sozlanmagan yoki xato bo'lsa — None
    (log yoziladi, istisno tashlanmaydi)."""
    if not sozlangan():
        return None

    url = f"http://{settings.KAMERA_IP}{settings.KAMERA_SNAPSHOT_YOLI}"
    try:
        javob = httpx.get(
            url,
            auth=httpx.DigestAuth(settings.KAMERA_LOGIN, settings.KAMERA_PAROL),
            timeout=settings.KAMERA_TIMEOUT_SONIYA,
        )
        javob.raise_for_status()
        baytlar = javob.content
        if not baytlar:
            logger.warning("Kamera bo'sh javob qaytardi: %s", url)
            return None
        return baytlar
    except Exception:  # noqa: BLE001 — kamera hech qachon operatorni bloklamasin
        logger.exception("Kameradan surat olishda xato (%s)", url)
        return None


def kip_uchun_surat_saqla(mahsulot_nomi: str, smena: str, vaqt: datetime) -> str | None:
    """Kameradan surat olib, STORAGE_PATH ostiga (rasm_saqla struktura bilan:
    <Oy>/<Kun>/Smena_<X>/<Mahsulot nomi>/) yozadi va bazaga saqlanadigan nisbiy
    yo'lni qaytaradi. Kamera sozlanmagan yoki xato bergan bo'lsa — None (kip
    suratsiz saqlanadi)."""
    try:
        baytlar = snapshot_ol()
        if baytlar is None:
            return None
        return rasm_saqla(baytlar, smena=smena, vaqt=vaqt, turi="kip", mahsulot_nomi=mahsulot_nomi)
    except Exception:  # noqa: BLE001 — saqlashda ham xato operatorni bloklamasin
        logger.exception("Kamera suratini saqlashda xato")
        return None

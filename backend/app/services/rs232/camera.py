import logging

import httpx

from app.core.config import settings

logger = logging.getLogger("camera")


def snapshot_ol() -> bytes | None:
    """IP kameraning HTTP snapshot manzilidan bitta JPEG oladi. Model/protokol
    aniqlangach (masalan RTSP kerak bo'lsa) faqat shu funksiya almashtiriladi."""
    if not settings.CAMERA_SNAPSHOT_URL:
        logger.warning("CAMERA_SNAPSHOT_URL sozlanmagan — surat olinmadi")
        return None
    try:
        javob = httpx.get(settings.CAMERA_SNAPSHOT_URL, timeout=5)
        javob.raise_for_status()
        return javob.content
    except httpx.HTTPError:
        logger.exception("Kameradan surat olishda xato")
        return None

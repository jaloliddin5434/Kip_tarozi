import logging

from app.models.partiya import Partiya

logger = logging.getLogger("nakladnoy")


def nakladnoy_raqami_yarat(partiya: Partiya) -> str:
    return f"NK-{partiya.id:06d}"


def nakladnoy_pdf_yarat(partiya: Partiya) -> str | None:
    """Stub — haqiqiy PDF generatsiyasi (Playwright, kompaniya namunasi bo'yicha)
    alohida so'ralganda qo'shiladi. Hozircha faqat nakladnoy raqami saqlanadi,
    fayl yaratilmaydi."""
    logger.info(
        "[NAKLADNOY STUB] Partiya #%s (id=%s) uchun nakladnoy so'raldi — PDF hali generatsiya qilinmaydi",
        partiya.partiya_raqami,
        partiya.id,
    )
    return None

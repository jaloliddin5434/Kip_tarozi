import logging
import threading
import time
from collections.abc import Callable

import httpx

from app.core.config import settings

logger = logging.getLogger("holat_xabarchisi")


class HolatXabarchisi:
    """AGENT_HOLAT_YUBORISH_SONIYA oralig'ida backendga 'salomatman' xabarini
    yuboradi (Dashboard'da ko'rsatish uchun). Best-effort — muvaffaqiyatsiz
    urinish saqlanmaydi, keyingi tsiklda qayta urinadi."""

    def __init__(self, holat_olish: Callable[[], dict]) -> None:
        self._holat_olish = holat_olish
        self._toxtatilsin = False
        self._thread: threading.Thread | None = None

    def ishga_tushir(self) -> None:
        self._toxtatilsin = False
        self._thread = threading.Thread(target=self._loop, daemon=True, name="holat-xabarchisi")
        self._thread.start()

    def toxtat(self) -> None:
        self._toxtatilsin = True
        if self._thread:
            self._thread.join(timeout=5)

    def _loop(self) -> None:
        while not self._toxtatilsin:
            try:
                httpx.post(
                    f"{settings.BACKEND_URL}/api/v1/agent-holat",
                    json=self._holat_olish(),
                    headers={"X-Agent-Key": settings.AGENT_API_KEY},
                    timeout=5,
                )
            except httpx.HTTPError as exc:
                logger.debug("Holat xabarini yuborib bo'lmadi: %s", exc)
            time.sleep(settings.AGENT_HOLAT_YUBORISH_SONIYA)

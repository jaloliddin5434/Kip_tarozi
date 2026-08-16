import logging
import threading
import time

import httpx

from app.core.config import settings
from app.services.rs232 import navbat

logger = logging.getLogger("sinxron")


class SinxronIshchisi:
    """Fon thread — internet/server aloqasi tiklanganda offline navbatdagi
    kiplarni AGENT_SYNC_INTERVAL_SONIYA oralig'ida backendga (/kiplar/sinxron)
    avtomatik yuboradi. Har elementning o'ziga xos operator tokeni saqlanadi."""

    def __init__(self) -> None:
        self._toxtatilsin = False
        self._thread: threading.Thread | None = None

    def ishga_tushir(self) -> None:
        self._toxtatilsin = False
        self._thread = threading.Thread(target=self._loop, daemon=True, name="sinxron-worker")
        self._thread.start()

    def toxtat(self) -> None:
        self._toxtatilsin = True
        if self._thread:
            self._thread.join(timeout=5)

    def _loop(self) -> None:
        while not self._toxtatilsin:
            try:
                self._urinish()
            except Exception:
                logger.exception("Sinxronlash tsiklida kutilmagan xato")
            time.sleep(settings.AGENT_SYNC_INTERVAL_SONIYA)

    def _urinish(self) -> None:
        elementlar = navbat.hammasini_olish()
        if not elementlar:
            return

        tokenlar: dict[str, list[dict]] = {}
        for element in elementlar:
            tokenlar.setdefault(element["token"], []).append(element)

        for token, guruh in tokenlar.items():
            try:
                javob = httpx.post(
                    f"{settings.BACKEND_URL}/api/v1/kiplar/sinxron",
                    json=[g["payload"] for g in guruh],
                    headers={"Authorization": f"Bearer {token}"},
                    timeout=15,
                )
                javob.raise_for_status()
            except httpx.HTTPError as exc:
                logger.warning("Sinxronlashda aloqa xatosi, keyingi tsiklda qayta urinamiz: %s", exc)
                return

            for natija in javob.json():
                if natija["holat"] in ("saqlandi", "allaqachon_mavjud"):
                    navbat.ochirish(natija["mijoz_id"])
                    logger.info("Sinxronlandi: %s -> %s", natija["mijoz_id"], natija["holat"])
                else:
                    navbat.xato_belgila(natija["mijoz_id"], natija.get("xabar") or "noma'lum xato")
                    logger.error("Sinxronlashda xato: %s -> %s", natija["mijoz_id"], natija.get("xabar"))

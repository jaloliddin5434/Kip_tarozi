import logging
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timezone

from app.core.config import settings
from app.services.rs232.reader import OgirlikOquvchi, RS232OqishXatosi

logger = logging.getLogger("rs232.watchdog")


@dataclass
class UlanishHolati:
    ulangan: bool = False
    oxirgi_xato: str | None = None
    oxirgi_ulanish_vaqt: datetime | None = None
    qayta_urinishlar: int = 0


class RS232Watchdog:
    """OgirlikOquvchi'ni fon thread'ida ishga tushiradi; port uzilsa yoki xato
    chiqsa RS232_RECONNECT_SECONDS oralig'ida qayta ulashga urinadi. Holat
    dashboard indikatori uchun .holat orqali ochiq."""

    def __init__(self, oquvchi: OgirlikOquvchi) -> None:
        self._oquvchi = oquvchi
        self.holat = UlanishHolati()
        self._thread: threading.Thread | None = None
        self._toxtatilsin = False

    def ishga_tushir(self) -> None:
        self._toxtatilsin = False
        self._thread = threading.Thread(target=self._loop, daemon=True, name="rs232-watchdog")
        self._thread.start()

    def toxtat(self) -> None:
        self._toxtatilsin = True
        self._oquvchi.uz()
        if self._thread:
            self._thread.join(timeout=5)

    def _loop(self) -> None:
        while not self._toxtatilsin:
            try:
                self._oquvchi.ulan()
                self.holat.ulangan = True
                self.holat.oxirgi_xato = None
                self.holat.oxirgi_ulanish_vaqt = datetime.now(timezone.utc)
                self.holat.qayta_urinishlar = 0
                logger.info("RS232 ulandi")
                self._oquvchi.oqish_tsikli()
            except RS232OqishXatosi as exc:
                self.holat.ulangan = False
                self.holat.oxirgi_xato = str(exc)
                self.holat.qayta_urinishlar += 1
                logger.warning(
                    "RS232 aloqasi uzildi (%s). %s soniyadan so'ng qayta urinish.",
                    exc,
                    settings.RS232_RECONNECT_SECONDS,
                )
            except Exception as exc:  # kutilmagan xato ham watchdog'ni to'xtatmasligi kerak
                self.holat.ulangan = False
                self.holat.oxirgi_xato = str(exc)
                self.holat.qayta_urinishlar += 1
                logger.exception("RS232 watchdog'da kutilmagan xato")

            if self._toxtatilsin:
                break
            time.sleep(settings.RS232_RECONNECT_SECONDS)

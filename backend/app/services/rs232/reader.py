import logging
import re
from datetime import datetime, timezone

import serial

from app.core.config import settings
from app.services.rs232.bus import OgirlikKanali

logger = logging.getLogger("rs232.reader")


class RS232OqishXatosi(Exception):
    pass


class OgirlikOquvchi:
    """Bitta seriya portidan uzluksiz o'qiydi va har bir qatorni RS232_REGEX bilan
    parslab, natijani OgirlikKanali orqali tarqatadi. Indikator modeli aniqlangach
    faqat RS232_REGEX (yoki shu klass) o'zgartiriladi — qolgan tizim o'zgarmaydi."""

    def __init__(self, kanal: OgirlikKanali) -> None:
        self._kanal = kanal
        self._regex = re.compile(settings.RS232_REGEX)
        self._port: serial.Serial | None = None
        self._toxtatilsin = False

    def ulan(self) -> None:
        self._port = serial.Serial(
            port=settings.RS232_PORT,
            baudrate=settings.RS232_BAUDRATE,
            bytesize=settings.RS232_BYTESIZE,
            parity=settings.RS232_PARITY,
            stopbits=settings.RS232_STOPBITS,
            timeout=settings.RS232_TIMEOUT,
        )
        logger.info("RS232 portga ulandi: %s", settings.RS232_PORT)

    def uz(self) -> None:
        self._toxtatilsin = True
        if self._port and self._port.is_open:
            self._port.close()

    def oqish_tsikli(self) -> None:
        """Bloklovchi tsikl — alohida thread'da chaqirilishi kerak.
        Portdan xato chiqsa RS232OqishXatosi ko'taradi, watchdog qayta ulaydi."""
        if self._port is None:
            raise RS232OqishXatosi("Port ulanmagan")

        self._toxtatilsin = False
        while not self._toxtatilsin:
            try:
                qator = self._port.readline().decode("ascii", errors="ignore").strip()
            except serial.SerialException as exc:
                raise RS232OqishXatosi(str(exc)) from exc

            if not qator:
                continue

            mos = self._regex.search(qator)
            if not mos:
                logger.debug("Parslanmadi: %r", qator)
                continue

            try:
                ogirlik = float(mos.group("vazn"))
            except (ValueError, IndexError):
                logger.warning("RS232_REGEX 'vazn' guruhini topa olmadi: %r", qator)
                continue

            self._kanal.eshittir(ogirlik, datetime.now(timezone.utc))

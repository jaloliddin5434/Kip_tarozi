import enum
import logging
import threading
from collections.abc import Callable
from datetime import datetime

from app.core.config import settings
from app.services.rs232.bus import OgirlikKanali

logger = logging.getLogger("anti_ogirlik")

HodisaYuboruvchi = Callable[[float, datetime, str | None, str | None], int | None]


class AntiOgirlikHolati(str, enum.Enum):
    bosh = "bosh"
    yuk_qoyildi = "yuk_qoyildi"
    bloklangan = "bloklangan"


class AntiOgirlikNazorati:
    """RS232 o'qish tsiklidan ALOHIDA, uzluksiz ishlaydigan state machine
    (OgirlikKanali'ga obuna bo'ladi — 'Saqlash' tugmasi bosilishidan mustaqil):

        bosh --[og'irlik >= THRESHOLD, barqaror]--> yuk_qoyildi
        yuk_qoyildi --[kip saqlandi]--> bosh
        yuk_qoyildi --[og'irlik < PASTGA_TUSHISH]--> bloklangan (+ hodisa yuboriladi)
        bloklangan --[operator tasdiqladi]--> bosh
    """

    def __init__(self, kanal: OgirlikKanali, hodisa_yuborish: HodisaYuboruvchi) -> None:
        self._holat = AntiOgirlikHolati.bosh
        self._barqaror_boshlanish: datetime | None = None
        self._lock = threading.Lock()
        self._hodisa_yuborish = hodisa_yuborish

        self.joriy_hodisa_id: int | None = None
        self.kontekst_mahsulot_kodi: str | None = None
        self.kontekst_smena: str | None = None

        kanal.obuna_bol(self._qabul_qil)

    @property
    def holat(self) -> AntiOgirlikHolati:
        return self._holat

    def kontekst_ornat(self, mahsulot_kodi: str | None, smena: str | None) -> None:
        self.kontekst_mahsulot_kodi = mahsulot_kodi
        self.kontekst_smena = smena

    def saqlandi_deb_belgila(self) -> None:
        """Kip muvaffaqiyatli saqlangan (yoki offline navbatga qo'yilgan) — normal
        yakun, hodisa yuborilmaydi."""
        with self._lock:
            if self._holat == AntiOgirlikHolati.yuk_qoyildi:
                self._holat = AntiOgirlikHolati.bosh
                self._barqaror_boshlanish = None

    def tasdiqlandi(self) -> None:
        """Operator 'Tushundim' bosdi — blok ochiladi."""
        with self._lock:
            self._holat = AntiOgirlikHolati.bosh
            self._barqaror_boshlanish = None
            self.joriy_hodisa_id = None

    def _qabul_qil(self, ogirlik: float, vaqt: datetime) -> None:
        with self._lock:
            if self._holat == AntiOgirlikHolati.bosh:
                if ogirlik >= settings.ANTI_OGIRLIK_THRESHOLD_KG:
                    if self._barqaror_boshlanish is None:
                        self._barqaror_boshlanish = vaqt
                    elif (vaqt - self._barqaror_boshlanish).total_seconds() >= settings.STABILITY_SECONDS:
                        self._holat = AntiOgirlikHolati.yuk_qoyildi
                        logger.info("Yuk qo'yildi deb aniqlandi: %.2f kg", ogirlik)
                else:
                    self._barqaror_boshlanish = None

            elif self._holat == AntiOgirlikHolati.yuk_qoyildi:
                if ogirlik < settings.ANTI_OGIRLIK_PASTGA_TUSHISH_KG:
                    self._holat = AntiOgirlikHolati.bloklangan
                    self._barqaror_boshlanish = None
                    logger.warning("YUK SAQLANMADI hodisasi: %.2f kg", ogirlik)
                    threading.Thread(
                        target=self._hodisani_royxatga_ol, args=(ogirlik, vaqt), daemon=True
                    ).start()

            # bloklangan holatda operator tasdiqlamaguncha hech narsa o'zgarmaydi

    def _hodisani_royxatga_ol(self, ogirlik: float, vaqt: datetime) -> None:
        try:
            self.joriy_hodisa_id = self._hodisa_yuborish(
                ogirlik, vaqt, self.kontekst_smena, self.kontekst_mahsulot_kodi
            )
        except Exception:
            logger.exception("Shubhali holatni backendga yuborishda xato")

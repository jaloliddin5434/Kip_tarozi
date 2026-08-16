import threading
from collections import deque
from dataclasses import dataclass
from datetime import datetime, timezone

from app.core.config import settings
from app.services.rs232.bus import OgirlikKanali


@dataclass
class Namuna:
    ogirlik: float
    vaqt: datetime


class BarqarorlikTekshiruvchisi:
    """OgirlikKanali'ga obuna bo'lib, so'nggi STABILITY_SECONDS ichidagi barcha
    o'lchamlar STABILITY_TOLERANCE_KG ichida tursa 'barqaror' deb hisoblaydi —
    shunda operator ekranida 'Saqlash' tugmasi faollashadi."""

    def __init__(self, kanal: OgirlikKanali) -> None:
        self._namunalar: deque[Namuna] = deque()
        self._lock = threading.Lock()
        self.joriy_ogirlik: float = 0.0
        kanal.obuna_bol(self._qabul_qil)

    def _qabul_qil(self, ogirlik: float, vaqt: datetime) -> None:
        with self._lock:
            self.joriy_ogirlik = ogirlik
            self._namunalar.append(Namuna(ogirlik, vaqt))
            chegara = vaqt.timestamp() - settings.STABILITY_SECONDS
            while self._namunalar and self._namunalar[0].vaqt.timestamp() < chegara:
                self._namunalar.popleft()

    def barqarormi(self) -> bool:
        with self._lock:
            if not self._namunalar:
                return False
            eng_eski = self._namunalar[0].vaqt
            hozir = datetime.now(timezone.utc)
            if (hozir - eng_eski).total_seconds() < settings.STABILITY_SECONDS:
                return False
            ogirliklar = [n.ogirlik for n in self._namunalar]
            return max(ogirliklar) - min(ogirliklar) <= settings.STABILITY_TOLERANCE_KG

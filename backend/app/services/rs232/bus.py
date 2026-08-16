import threading
from collections.abc import Callable
from datetime import datetime

VazniyTinglovchi = Callable[[float, datetime], None]


class OgirlikKanali:
    """Oddiy pub-sub: RS232'dan o'qilgan har bir og'irlik shu yerga yuboriladi,
    stability-checker va anti-o'g'irlik nazorati (2-bosqich) shu kanalga obuna bo'ladi."""

    def __init__(self) -> None:
        self._tinglovchilar: list[VazniyTinglovchi] = []
        self._lock = threading.Lock()

    def obuna_bol(self, tinglovchi: VazniyTinglovchi) -> None:
        with self._lock:
            self._tinglovchilar.append(tinglovchi)

    def eshittir(self, ogirlik: float, vaqt: datetime) -> None:
        with self._lock:
            tinglovchilar = list(self._tinglovchilar)
        for tinglovchi in tinglovchilar:
            tinglovchi(ogirlik, vaqt)

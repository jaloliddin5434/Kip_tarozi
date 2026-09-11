import logging
import threading
import time

import httpx

from app.core.config import settings
from app.services.rs232 import navbat

logger = logging.getLogger("sinxron")

# AUDIT TOPILMASI (tuzatilmoqda): avval butun navbat (bitta operator tokeni
# uchun barcha kutilayotgan yozuvlar) BITTA so'rovda yuborilardi. Agar
# operator bir necha kun offline ishlab navbatda yuzlab-minglab yozuv
# to'plansa, bitta so'rovda buncha ko'pini qayta ishlash (backend har bir
# kip uchun DB yozuv + ba'zan sinxron Telegram so'rovi ham qiladi) eski
# 15s timeout'dan doim oshib ketardi — so'rov HECH QACHON muvaffaqiyatli
# tugamas, navbat abadiy o'sha katta holatda qolib, cheksiz qayta urinardi.
#
# Endi navbat KICHIK BO'LAKLARGA (_BOLAK_HAJMI tadan) bo'lib yuboriladi —
# har bo'lak muvaffaqiyatli bo'lgach DARHOL navbatdan o'chiriladi (pastga
# qarang, `navbat.ochirish` har natija uchun alohida chaqiriladi), shuning
# uchun keyingi bo'lak (yoki tsikl) muvaffaqiyatsiz bo'lsa ham oldingi
# bo'laklar yo'qolmaydi — navbat vaqt o'tishi bilan MUQARRAR qisqarib
# boradi (o'zini davolaydi), hech qachon "abadiy qotib qolmaydi".
# Timeout ham (15s -> 60s) — bo'lak hajmi (50) bilan birga hisoblanganda
# har yozuvga ~1.2s byudjet beradi, bu normal DB+Telegram vaqtini qamrab
# oladi. Agar baribir timeout bo'lsa ham — `mijoz_id` orqali idempotentlik
# tufayli xavfsiz (dublikat yaratilmaydi), keyingi urinish shu bo'lakni
# qaytadan yuboradi.
_BOLAK_HAJMI = 50
_SOROV_TIMEOUT_SONIYA = 60


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
            jami_bolaklar = (len(guruh) + _BOLAK_HAJMI - 1) // _BOLAK_HAJMI
            for i in range(0, len(guruh), _BOLAK_HAJMI):
                bolak = guruh[i : i + _BOLAK_HAJMI]
                bolak_raqami = i // _BOLAK_HAJMI + 1
                try:
                    javob = httpx.post(
                        f"{settings.BACKEND_URL}/api/v1/kiplar/sinxron",
                        json=[g["payload"] for g in bolak],
                        headers={"Authorization": f"Bearer {token}"},
                        timeout=_SOROV_TIMEOUT_SONIYA,
                    )
                    javob.raise_for_status()
                except httpx.HTTPError as exc:
                    logger.warning(
                        "Sinxronlashda aloqa xatosi (bo'lak %s/%s, %s ta yozuv) — bu va navbatdagi "
                        "bo'laklar/tokenlar KEYINGI TSIKLDA qayta uriniladi, oldingi bo'laklar allaqachon "
                        "navbatdan o'chirilgan (yo'qolmagan): %s",
                        bolak_raqami,
                        jami_bolaklar,
                        len(bolak),
                        exc,
                    )
                    return

                for natija in javob.json():
                    if natija["holat"] in ("saqlandi", "allaqachon_mavjud"):
                        navbat.ochirish(natija["mijoz_id"])
                        logger.info("Sinxronlandi: %s -> %s", natija["mijoz_id"], natija["holat"])
                    else:
                        navbat.xato_belgila(natija["mijoz_id"], natija.get("xabar") or "noma'lum xato")
                        logger.error("Sinxronlashda xato: %s -> %s", natija["mijoz_id"], natija.get("xabar"))

"""UZEX (O'zbekiston Respublika tovar-xom ashyo birjasi, uzex.uz) dan paxta
tolasi va yon mahsulotlari uchun joriy narxlarni oladi.

Manba: https://uzex.uz/Quote/GetQuotes — bu UZEX bosh sahifasidagi "kunlik
kotirovkalar" satri uchun ishlatiladigan ochiq JSON endpoint. Har element:
    {"name": "Paxta tola 1 nav 4 tip (oliy) 2025-yil hosili",
     "summa": "20 222 078.05",   # so'm / TONNA
     "difference": "...", "percent": "...", "tovarNum": 0}

Bu ro'yxat UZEX tomonidan tanlab qo'yiladi va o'zgarib turadi — odatda
paxta tolasi ("Paxta tola ...") doim bo'ladi, Lint/momiq/o'lik paxta esa
har doim ham bo'lmaydi. Topilmagan mahsulot STUB (zaxira) qiymatida qoladi.

Ishonchlilik:
  * natija 1 soat keshlanadi (UZEX'ga ortiqcha yuk bermaslik uchun);
  * so'rov muvaffaqiyatsiz bo'lsa yoki javob kutilmagan bo'lsa — eski kesh
    (bo'lsa), aks holda STUB qiymatlar qaytariladi, xato yutiladi;
  * `yangilangan_vaqt` HAQIQIY oxirgi muvaffaqiyatli olingan vaqtni bildiradi.
"""

import logging
from datetime import datetime, timedelta, timezone

import httpx

logger = logging.getLogger("uzex")

UZEX_QUOTES_URL = "https://uzex.uz/Quote/GetQuotes"
KESH_MUDDATI = timedelta(hours=1)
SOROV_KUTISH_SONIYA = 8.0

# (kod, nomi, zaxira narx so'm/kg) — UZEX'dan real qiymat olinmasa shu qoladi.
# Qiymatlar avvalgi _UZEX_STUB bilan bir xil (regressiya bo'lmasligi uchun).
STUB_NARXLAR: tuple[tuple[str, str, float], ...] = (
    ("tola", "Tola", 18_500.0),
    ("lint", "Lint", 12_000.0),
    ("pux", "Pux", 6_500.0),
    ("ulyuk", "Ulyuk", 4_000.0),
)

# Har mahsulotimiz uchun UZEX nomidagi kalit so'zlar:
#   ("bo'lishi kerak bo'lgan qismlar", "bo'lmasligi kerak bo'lgan qismlar").
# UZEX nomlari lotin transliteratsiyasida keladi, solishtirish kichik harfda.
_MOS_KELISH: dict[str, tuple[tuple[str, ...], tuple[str, ...]]] = {
    "tola": (("paxta tola",), ("yog", "chigit", "shrot", "chiqindi", "o‘lik", "olik", "momi")),
    "lint": (("lint",), ()),
    "pux": (("paxta momi", "paxta momig"), ("chiqindi", "siklon")),
    "ulyuk": (("o‘lik paxta", "olik paxta", "ulyuk"), ()),
}

# Modul darajasidagi oddiy kesh: {"vaqt": datetime|None, "narxlar": list|None}
_kesh: dict = {"vaqt": None, "narxlar": None}


def keshni_tozalash() -> None:
    """Asosan testlar uchun — modul keshini bo'shatadi."""
    _kesh["vaqt"] = None
    _kesh["narxlar"] = None


def _sonni_ajrat(matn: str) -> float | None:
    """'20 222 078.05' -> 20222078.05 ; '13 984 068,00' -> 13984068.0"""
    s = matn.replace("\xa0", "").replace(" ", "").strip()
    if not s:
        return None
    if "," in s and "." in s:
        s = s.replace(",", "")  # vergul — minglik ajratgich
    elif "," in s:
        s = s.replace(",", ".")  # vergul — o'nlik ajratgich
    try:
        qiymat = float(s)
    except ValueError:
        return None
    return qiymat if qiymat > 0 else None


def _json_dan_narxlar(elementlar: list) -> dict[str, float]:
    """UZEX quote-JSON ro'yxatidan har mahsulotimiz uchun so'm/KG narx.
    so'm/tonna -> so'm/kg (/1000). Bir nechta mos qator bo'lsa — o'rtacha."""
    yigilgan: dict[str, list[float]] = {}
    for el in elementlar:
        if not isinstance(el, dict):
            continue
        nomi = str(el.get("name") or "").lower()
        tonna_narx = _sonni_ajrat(str(el.get("summa") or ""))
        if tonna_narx is None:
            continue
        for kod, (ichida, tashqarida) in _MOS_KELISH.items():
            if any(k in nomi for k in ichida) and not any(x in nomi for x in tashqarida):
                yigilgan.setdefault(kod, []).append(tonna_narx / 1000.0)
    return {kod: round(sum(v) / len(v), 2) for kod, v in yigilgan.items()}


def _uzexdan_ol() -> dict[str, float]:
    """UZEX'ga so'rov yuboradi va {kod: narx_som_kg} qaytaradi. Xatolarda
    (tarmoq, HTTP, JSON, kutilmagan struktura, paxta topilmadi) — Exception."""
    javob = httpx.get(
        UZEX_QUOTES_URL,
        timeout=SOROV_KUTISH_SONIYA,
        follow_redirects=True,
        headers={
            "User-Agent": "Mozilla/5.0 (compatible; KipTaroziBot/1.0)",
            "X-Requested-With": "XMLHttpRequest",
            "Accept": "application/json, text/plain, */*",
        },
    )
    javob.raise_for_status()
    elementlar = javob.json()
    if not isinstance(elementlar, list):
        raise ValueError("UZEX javobi kutilgan JSON ro'yxat emas")
    narxlar = _json_dan_narxlar(elementlar)
    if not narxlar:
        raise ValueError("UZEX kotirovkalarida paxta mahsuloti topilmadi")
    return narxlar


def uzex_narxlari() -> tuple[list[tuple[str, str, float]], datetime]:
    """((kod, nomi, narx_som_kg), ...) ro'yxati va oxirgi MUVAFFAQIYATLI
    olingan vaqt (UTC).

    - Kesh yangi (< 1 soat) bo'lsa — keshdan qaytadi.
    - Aks holda UZEX'dan olishga urinadi. Muvaffaqiyatsiz bo'lsa: eski kesh
      (bo'lsa) yoki STUB qiymatlar. Har mahsulot alohida: UZEX'da topilmagani
      o'zining STUB qiymatida qoladi.
    """
    hozir = datetime.now(timezone.utc)

    if _kesh["narxlar"] is not None and (hozir - _kesh["vaqt"]) < KESH_MUDDATI:
        return _kesh["narxlar"], _kesh["vaqt"]

    try:
        real = _uzexdan_ol()
    except Exception as xato:  # noqa: BLE001 — har qanday xatoda yumshoq degradatsiya
        logger.warning("UZEX narxlarini olib bo'lmadi (%s) — %s", type(xato).__name__, xato)
        if _kesh["narxlar"] is not None:
            return _kesh["narxlar"], _kesh["vaqt"]
        return [(kod, nomi, stub) for kod, nomi, stub in STUB_NARXLAR], hozir

    narxlar = [(kod, nomi, real.get(kod, stub)) for kod, nomi, stub in STUB_NARXLAR]
    manba = ", ".join(f"{kod}={real[kod]}" for kod in real)
    logger.info("UZEX narxlari yangilandi: %s", manba)
    _kesh["narxlar"] = narxlar
    _kesh["vaqt"] = hozir
    return narxlar, hozir

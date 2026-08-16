from datetime import date, timedelta

DavrTuri = str  # "kunlik" | "haftalik" | "oylik" | "mavsum"


def mavsum_boshlanishi(sana: date) -> date:
    """Mavsum har yili 1-sentyabrdan boshlanadi."""
    if sana.month >= 9:
        return date(sana.year, 9, 1)
    return date(sana.year - 1, 9, 1)


def davr_oraligi(davr: DavrTuri, sana: date) -> tuple[date, date]:
    if davr == "kunlik":
        return sana, sana

    if davr == "haftalik":
        boshlanish = sana - timedelta(days=sana.weekday())  # dushanba
        return boshlanish, boshlanish + timedelta(days=6)

    if davr == "oylik":
        boshlanish = sana.replace(day=1)
        keyingi_oy_boshi = (boshlanish.replace(day=28) + timedelta(days=4)).replace(day=1)
        return boshlanish, keyingi_oy_boshi - timedelta(days=1)

    if davr == "mavsum":
        return mavsum_boshlanishi(sana), sana

    raise ValueError(f"Noma'lum davr turi: {davr}")

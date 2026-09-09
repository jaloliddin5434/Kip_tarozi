"""Zaxira nusxasi uchun surat fayllariga tushunarli nom xaritasini tuzadi.

`scripts\\backup_yarat.ps1` shu skriptni chaqiradi. Skript bazadan har bir
kipning `surat_yoli` va uni tavsiflovchi ma'lumotlarni (mahsulot nomi, partiya
raqami, kip raqami, og'irlik) o'qib, quyidagi xaritani JSON ko'rinishida
chiqaradi:

    {
      "2026-09/2026-09-09/Smena_A/Tola/d6d8e44f....jpg": "Tola_Partiya55_Kip4_142.6kg.jpg",
      ...
    }

Kalit — bazadagi `surat_yoli` (STORAGE_PATH'ga nisbiy, "/" bilan).
Qiymat — zaxira nusxasida ishlatiladigan yangi, o'qishga qulay fayl nomi.

MUHIM: bu skript bazadan FAQAT O'QIYDI va ASL `storage/` papkasiga TEGMAYDI.
Qayta nomlash faqat zaxira (backup) nusxasida, PowerShell tomonida bo'ladi —
dastur bazada asl (hash) nomga bog'liq bo'lgani uchun asl fayllar
o'zgartirilmaydi.

    python -m scripts.storage_backup_metadata [--output xarita.json]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from decimal import Decimal, InvalidOperation
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

# Windows fayl nomida ishlatib bo'lmaydigan belgilar + boshqaruv belgilari.
_YAROQSIZ = re.compile(r'[<>:"/\\|?*\x00-\x1f]')


def xavfsiz_nom(matn: str) -> str:
    """Fayl nomi bo'lagini xavfsiz holga keltiradi: yaroqsiz belgilar va bo'sh
    joy "_" ga aylanadi, ketma-ket "_" bittaga qisqaradi, chetdagi "_" va "."
    olib tashlanadi. Bo'sh qolsa "nomsiz" qaytadi."""
    matn = (matn or "").strip()
    matn = _YAROQSIZ.sub("_", matn)
    matn = re.sub(r"\s+", "_", matn)
    matn = re.sub(r"_+", "_", matn)
    return matn.strip("_.") or "nomsiz"


def ogirlik_matni(qiymat) -> str:
    """Og'irlikni ixcham matnga o'giradi: 142.60 -> "142.6", 142.00 -> "142",
    0.50 -> "0.5". Tushunib bo'lmasa "0"."""
    try:
        d = Decimal(str(qiymat))
    except (InvalidOperation, ValueError, TypeError):
        return "0"
    s = f"{d:.2f}"
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return s or "0"


def nom_yasa(
    mahsulot: str,
    partiya_raqami,
    kip_raqami,
    ogirlik,
    kengaytma: str = ".jpg",
) -> str:
    """<Mahsulot>_Partiya<raqam>_Kip<raqam>_<ogirlik>kg<kengaytma>

    Masalan: nom_yasa("Tola", 55, 4, Decimal("142.60")) -> "Tola_Partiya55_Kip4_142.6kg.jpg"
    """
    ozak = "{m}_Partiya{p}_Kip{k}_{v}kg".format(
        m=xavfsiz_nom(str(mahsulot)),
        p=int(partiya_raqami),
        k=int(kip_raqami),
        v=ogirlik_matni(ogirlik),
    )
    if not kengaytma.startswith("."):
        kengaytma = "." + kengaytma
    return xavfsiz_nom(ozak) + kengaytma.lower()


def xarita_yasa(qatorlar) -> dict[str, str]:
    """qatorlar: (surat_yoli, mahsulot_nomi, partiya_raqami, kip_raqami, ogirlik)
    ko'rinishidagi ketma-ketlik.

    Natija: {surat_yoli (nisbiy, "/" bilan): yangi_fayl_nomi}. `surat_yoli`
    bo'sh bo'lgan qatorlar tashlab ketiladi. Ikki xil surat bir xil nomga
    to'g'ri kelsa, ikkinchisiga "_2", "_3", ... qo'shiladi."""
    xarita: dict[str, str] = {}
    band: dict[str, str] = {}  # nom (kichik harf) -> surat_yoli

    for qator in qatorlar:
        surat_yoli, mahsulot, partiya_raqami, kip_raqami, ogirlik = qator
        if not surat_yoli:
            continue

        nisbiy = str(surat_yoli).replace("\\", "/").lstrip("/")
        kengaytma = Path(nisbiy).suffix or ".jpg"

        try:
            nom = nom_yasa(mahsulot, partiya_raqami, kip_raqami, ogirlik, kengaytma)
        except (TypeError, ValueError):
            # Raqam maydonlari kutilmagan qiymatda bo'lsa — asl nomda qoldiramiz
            # (PowerShell tomoni bu kalitni topmasa, faylni o'zgartirmaydi).
            continue

        temel = nom
        i = 2
        while nom.lower() in band and band[nom.lower()] != nisbiy:
            p = Path(temel)
            nom = f"{p.stem}_{i}{p.suffix}"
            i += 1

        band[nom.lower()] = nisbiy
        xarita[nisbiy] = nom

    return xarita


def _bazadan_qatorlar():
    from sqlalchemy import select

    from app.core.database import SessionLocal
    from app.models.kip import Kip
    from app.models.mahsulot import Mahsulot
    from app.models.partiya import Partiya

    db = SessionLocal()
    try:
        return db.execute(
            select(
                Kip.surat_yoli,
                Mahsulot.nomi,
                Partiya.partiya_raqami,
                Kip.kip_raqami,
                Kip.ogirlik,
            )
            .join(Partiya, Kip.partiya_id == Partiya.id)
            .join(Mahsulot, Partiya.mahsulot_id == Mahsulot.id)
            .where(Kip.surat_yoli.is_not(None))
        ).all()
    finally:
        db.close()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Zaxira uchun surat fayl nomlari xaritasini (JSON) chiqaradi."
    )
    parser.add_argument("--output", "-o", help="JSON fayl yo'li (berilmasa — stdout).")
    args = parser.parse_args()

    xarita = xarita_yasa(_bazadan_qatorlar())
    matn = json.dumps(xarita, ensure_ascii=False, indent=1, sort_keys=True)

    if args.output:
        Path(args.output).write_text(matn, encoding="utf-8")
        print(f"{len(xarita)} ta yozuv -> {args.output}")
    else:
        print(matn)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

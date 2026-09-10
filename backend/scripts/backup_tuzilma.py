"""Zaxira nusxasi uchun "tushunarli tuzilma" yasaydi (Rasm / Excel / Nakladnoy).

`scripts\\backup_yarat.ps1` shu skriptni chaqiradi. Skript bazadan REAL VAQTDA
o'qib, berilgan `--dest` papkasi ichida quyidagini yaratadi:

    <dest>/
    ├── KIP-Tarozi Rasm/<Oy>/<DD.MM.YYYY>/Smena_<X>/<Mahsulot>/<tushunarli nom>.jpg
    ├── KIP-Tarozi Excel/<Oy>/<DD.MM.YYYY>/Smena_<X>/<Mahsulot>/Smena_<X>_<Mahsulot>_<YYYY-MM-DD>.xlsx
    └── KIP-Tarozi Nakladnoy/<nakladnoy_raqami>.pdf

- "KIP-Tarozi Rasm" — `storage/` ichidagi kip suratlari, tushunarli nom bilan
  (`storage_backup_metadata.nom_yasa`), faqat HISOBGA OLINADIGAN kiplar
  (aktiv + tahrirlangan; bekor qilinganlar `storage-xom/` xom nusxada qoladi).
- "KIP-Tarozi Excel" — har REAL kunlik (sana + smena + mahsulot) kombinatsiyasi
  uchun (o'sha kuni/smenada shu mahsulotdan kamida 1 ta hisobga olinadigan kip)
  `hisobotlar` moduli mantig'i bilan generatsiya qilinadi (fayl DISKDA saqlanmaydi,
  shu yerda yangidan yasaladi).
- "KIP-Tarozi Nakladnoy" — `storage/nakladnoy/*.pdf` (sotuv nakladnoylari).

MUHIM: bu skript bazadan FAQAT O'QIYDI va ASL `storage/` papkasiga TEGMAYDI.
Har qanday fayl xatosi (surat topilmadi va h.k.) — WARN bilan log qilinadi,
skript to'xtamaydi.

    python -m scripts.backup_tuzilma --dest "C:\\...\\storage_2026-09-10_2000"
"""

from __future__ import annotations

import argparse
import shutil
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import func, select

from app.core.config import settings
from app.models.foydalanuvchi import Smena
from app.models.kip import HISOBLANADIGAN_HOLATLAR, Kip
from app.models.mahsulot import Mahsulot
from app.models.partiya import Partiya
from app.services.hisobotlar_excel import smena_mahsulot_jadval
from scripts.storage_backup_metadata import nom_yasa, xavfsiz_nom

RASM_PAPKA = "KIP-Tarozi Rasm"
EXCEL_PAPKA = "KIP-Tarozi Excel"
NAKLADNOY_PAPKA = "KIP-Tarozi Nakladnoy"

# routes/hisobotlar.py:_OY_NOMLARI bilan bir xil yozuv (loyiha bo'ylab izchil).
_OY_NOMLARI = {
    1: "Yanvar", 2: "Fevral", 3: "Mart", 4: "Aprel", 5: "May", 6: "Iyun",
    7: "Iyul", 8: "Avgust", 9: "Sentabr", 10: "Oktabr", 11: "Noyabr", 12: "Dekabr",
}


def _log(matn: str) -> None:
    print(matn, flush=True)


def _kun(qiymat) -> date:
    """`func.date(...)` natijasi ba'zi drayverlarda `date`, ba'zilarida matn."""
    return qiymat if isinstance(qiymat, date) else date.fromisoformat(str(qiymat)[:10])


def _kun_papkasi(kun: date) -> str:
    return kun.strftime("%d.%m.%Y")


def _nokrar_yol(papka: Path, nom: str, band: set[str]) -> Path:
    """Papka ichida nom to'qnashsa "_2", "_3", ... qo'shadi (papkaga xos)."""
    p = Path(nom)
    natija = nom
    i = 2
    while natija.lower() in band:
        natija = f"{p.stem}_{i}{p.suffix}"
        i += 1
    band.add(natija.lower())
    return papka / natija


def suratlarni_joylashtir(db, dest: Path, storage_path: Path) -> dict:
    """Har bir HISOBGA OLINADIGAN, surati bor kipni
    `KIP-Tarozi Rasm/<Oy>/<Kun>/Smena_<X>/<Mahsulot>/<tushunarli>.jpg` ga
    nusxalaydi."""
    qatorlar = db.execute(
        select(
            func.date(Kip.vaqt),
            Kip.smena,
            Mahsulot.nomi,
            Kip.surat_yoli,
            Partiya.partiya_raqami,
            Kip.kip_raqami,
            Kip.ogirlik,
        )
        .join(Partiya, Partiya.id == Kip.partiya_id)
        .join(Mahsulot, Mahsulot.id == Partiya.mahsulot_id)
        .where(Kip.holati.in_(HISOBLANADIGAN_HOLATLAR), Kip.surat_yoli.is_not(None))
        .order_by(func.date(Kip.vaqt), Kip.smena, Mahsulot.nomi, Kip.kip_raqami)
    ).all()

    natija = {"nusxalandi": 0, "topilmadi": 0, "xato": 0}
    band_papka: dict[Path, set[str]] = {}

    for kun_x, smena, mahsulot_nomi, surat_yoli, partiya_raqami, kip_raqami, ogirlik in qatorlar:
        manba = storage_path / str(surat_yoli).replace("\\", "/").lstrip("/")
        if not manba.is_file():
            natija["topilmadi"] += 1
            _log(f"  [rasm] WARN surat topilmadi: {surat_yoli}")
            continue

        kun = _kun(kun_x)
        kengaytma = manba.suffix or ".jpg"
        papka = (
            dest
            / RASM_PAPKA
            / _OY_NOMLARI[kun.month]
            / _kun_papkasi(kun)
            / f"Smena_{smena.value}"
            / xavfsiz_nom(str(mahsulot_nomi))
        )
        try:
            nom = nom_yasa(mahsulot_nomi, partiya_raqami, kip_raqami, ogirlik, kengaytma)
        except (TypeError, ValueError):
            nom = manba.name

        band = band_papka.setdefault(papka, set())
        nishon = _nokrar_yol(papka, nom, band)
        try:
            papka.mkdir(parents=True, exist_ok=True)
            shutil.copy2(manba, nishon)
            natija["nusxalandi"] += 1
        except OSError as exc:
            natija["xato"] += 1
            _log(f"  [rasm] WARN nusxalab bo'lmadi {surat_yoli}: {exc}")

    return natija


def excel_kombinatsiyalari(db) -> list[tuple[date, Smena, int]]:
    """(sana, smena, mahsulot_id) — o'sha kuni/smenada shu mahsulotdan kamida
    1 ta hisobga olinadigan kip tortilgan kombinatsiyalar."""
    qatorlar = db.execute(
        select(func.date(Kip.vaqt), Kip.smena, Partiya.mahsulot_id)
        .join(Partiya, Partiya.id == Kip.partiya_id)
        .where(Kip.holati.in_(HISOBLANADIGAN_HOLATLAR))
        .group_by(func.date(Kip.vaqt), Kip.smena, Partiya.mahsulot_id)
        .order_by(func.date(Kip.vaqt), Kip.smena, Partiya.mahsulot_id)
    ).all()
    return [(_kun(k), s, m) for k, s, m in qatorlar]


def excellarni_yasa(db, dest: Path) -> dict:
    """Har kombinatsiya uchun `smena_mahsulot_jadval()` bilan Excel yasab,
    `KIP-Tarozi Excel/<Oy>/<Kun>/Smena_<X>/<Mahsulot>/` ga saqlaydi."""
    natija = {"yasaldi": 0, "xato": 0}
    for kun, smena, mahsulot_id in excel_kombinatsiyalari(db):
        mahsulot = db.get(Mahsulot, mahsulot_id)
        if mahsulot is None:
            continue
        try:
            wb = smena_mahsulot_jadval(db, kun, smena, mahsulot)
            papka = (
                dest
                / EXCEL_PAPKA
                / _OY_NOMLARI[kun.month]
                / _kun_papkasi(kun)
                / f"Smena_{smena.value}"
                / xavfsiz_nom(str(mahsulot.nomi))
            )
            papka.mkdir(parents=True, exist_ok=True)
            nom_qismi = mahsulot.nomi.replace(" ", "_") or mahsulot.kod
            wb.save(papka / f"Smena_{smena.value}_{nom_qismi}_{kun.isoformat()}.xlsx")
            natija["yasaldi"] += 1
        except Exception as exc:  # noqa: BLE001 — bitta kombinatsiya xatosi butun zaxrani to'xtatmasin
            natija["xato"] += 1
            _log(f"  [excel] WARN {kun} Smena_{smena.value} mahsulot#{mahsulot_id}: {exc}")
    return natija


def nakladnoylarni_kochir(dest: Path, storage_path: Path) -> dict:
    """`storage/nakladnoy/*.pdf` -> `KIP-Tarozi Nakladnoy/` (tekis nusxa)."""
    natija = {"nusxalandi": 0, "xato": 0}
    manba_papka = storage_path / "nakladnoy"
    if not manba_papka.is_dir():
        return natija

    nishon_papka = dest / NAKLADNOY_PAPKA
    for pdf in sorted(manba_papka.glob("*.pdf")):
        try:
            nishon_papka.mkdir(parents=True, exist_ok=True)
            shutil.copy2(pdf, nishon_papka / pdf.name)
            natija["nusxalandi"] += 1
        except OSError as exc:
            natija["xato"] += 1
            _log(f"  [nakladnoy] WARN {pdf.name}: {exc}")
    return natija


def tuzilma_yasa(dest: Path) -> dict:
    """Bazadan o'qib, `dest` ichida uch papkani (Rasm/Excel/Nakladnoy) to'ldiradi."""
    from app.core.database import SessionLocal

    storage_path = Path(settings.STORAGE_PATH)
    dest.mkdir(parents=True, exist_ok=True)

    db = SessionLocal()
    try:
        rasm = suratlarni_joylashtir(db, dest, storage_path)
        excel = excellarni_yasa(db, dest)
    finally:
        db.close()
    nakladnoy = nakladnoylarni_kochir(dest, storage_path)

    _log(
        "  [rasm] nusxalandi=%(nusxalandi)d topilmadi=%(topilmadi)d xato=%(xato)d" % rasm
    )
    _log("  [excel] yasaldi=%(yasaldi)d xato=%(xato)d" % excel)
    _log("  [nakladnoy] nusxalandi=%(nusxalandi)d xato=%(xato)d" % nakladnoy)
    return {"rasm": rasm, "excel": excel, "nakladnoy": nakladnoy}


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Zaxira uchun Rasm/Excel/Nakladnoy tuzilmasini yasaydi."
    )
    parser.add_argument("--dest", "-d", required=True, help="storage_YYYY-MM-DD_HHmm papkasi yo'li.")
    args = parser.parse_args()

    dest = Path(args.dest)
    _log(f"backup_tuzilma: {dest}")
    tuzilma_yasa(dest)
    _log("backup_tuzilma: tayyor.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

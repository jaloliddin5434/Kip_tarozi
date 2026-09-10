"""Boshlang'ich ma'lumotlarni yozadi: 4 ta fixed mahsulot, standart stansiya
va birinchi admin foydalanuvchi. Baza migratsiyadan o'tgach bir marta ishga
tushiriladi:

    python -m scripts.seed
"""

import getpass
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import select

from app.core.database import SessionLocal
from app.core.security import parolni_hash
from app.models.foydalanuvchi import Foydalanuvchi, Rol
from app.models.mahsulot import Mahsulot
from app.models.sozlama import Sozlama
from app.models.stansiya import Stansiya

MAHSULOTLAR = [
    ("tola", "Tola"),
    ("lint", "Lint"),
    ("pux", "Pux"),
    ("ulyuk", "Ulyuk"),
]

# Butun ilovadagi "mavsum" davri (Statistika, Dashboard, Rekord, Moliyaviy,
# Mavsum jurnali) shu sanadan boshlanadi. Admin panelidan (Sozlamalar)
# o'zgartirilishi mumkin.
SOZLAMALAR = [
    ("mavsum_boshlanish_sanasi", "2025-09-01", "Mavsum davri qaysi sanadan boshlanadi (YYYY-MM-DD)"),
]


def mahsulotlarni_yoz(db) -> None:
    for kod, nomi in MAHSULOTLAR:
        mavjud = db.scalar(select(Mahsulot).where(Mahsulot.kod == kod))
        if not mavjud:
            db.add(Mahsulot(kod=kod, nomi=nomi))
            print(f"  + mahsulot qo'shildi: {nomi}")


def sozlamalarni_yoz(db) -> None:
    for kalit, qiymat, tavsif in SOZLAMALAR:
        if db.get(Sozlama, kalit) is None:
            db.add(Sozlama(kalit=kalit, qiymat=qiymat, tavsif=tavsif))
            print(f"  + sozlama qo'shildi: {kalit}={qiymat}")


def stansiyani_yoz(db) -> None:
    mavjud = db.scalar(select(Stansiya).where(Stansiya.nomi == "Stansiya-1"))
    if not mavjud:
        db.add(Stansiya(nomi="Stansiya-1", rs232_port="COM3", rs232_baudrate=9600))
        print("  + standart stansiya qo'shildi: Stansiya-1")


def adminni_yoz(db) -> None:
    mavjud = db.scalar(select(Foydalanuvchi).where(Foydalanuvchi.rol == Rol.admin))
    if mavjud:
        print("  = admin allaqachon mavjud, o'tkazib yuborildi")
        return

    print("Birinchi admin foydalanuvchi yaratiladi:")
    login = input("  Login: ").strip()
    ism = input("  Ism: ").strip()
    parol = getpass.getpass("  Parol: ")

    db.add(
        Foydalanuvchi(
            ism=ism or login,
            login=login,
            parol_hash=parolni_hash(parol),
            rol=Rol.admin,
        )
    )
    print(f"  + admin qo'shildi: {login}")


def main() -> None:
    db = SessionLocal()
    try:
        mahsulotlarni_yoz(db)
        sozlamalarni_yoz(db)
        stansiyani_yoz(db)
        adminni_yoz(db)
        db.commit()
        print("Tayyor.")
    finally:
        db.close()


if __name__ == "__main__":
    main()

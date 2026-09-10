"""Testlar haqiqiy PostgreSQL'ga muhtoj (JSONB, native enum kabi
postgres-xos turlar ishlatilgani uchun SQLite ishlamaydi).

Ishga tushirish:
    createdb kip_tarozi_test        # (yoki DATABASE_URL'dagi nom + "_test")
    pytest

Agar test bazasi boshqa manzilda bo'lsa, TEST_DATABASE_URL environment
o'zgaruvchisini o'rnating. Baza topilmasa, DB'ga bog'liq testlar avtomatik
skip qilinadi (pure-logic testlar — masalan test_davr.py — baribir ishlaydi)."""

import os
from urllib.parse import urlsplit, urlunsplit

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.core.config import settings
from app.core.database import get_db
from app.core.security import parolni_hash, token_yarat
from app.main import app as fastapi_app
from app.models import Base
from app.models.foydalanuvchi import Foydalanuvchi, Rol, Smena
from app.models.mahsulot import Mahsulot
from app.models.stansiya import Stansiya


@pytest.fixture(autouse=True)
def _kamera_ochirilgan(monkeypatch):
    """Testlar HECH QACHON real IP kameraga chiqmasligi kerak. .env'da haqiqiy
    KAMERA_* qiymatlari bo'lsa ham, har bir testda ular o'chiriladi — kamera
    integratsiyasini sinaydigan testlar (test_kamera.py) o'zi qayta yoqadi."""
    monkeypatch.setattr(settings, "KAMERA_IP", None)
    monkeypatch.setattr(settings, "KAMERA_LOGIN", None)
    monkeypatch.setattr(settings, "KAMERA_PAROL", None)


@pytest.fixture(autouse=True)
def _telegram_polling_ochirilgan(monkeypatch):
    """`client` fixture FastAPI lifespan'ini ishga tushiradi, u esa
    telegram_polling threadini boshlaydi — agar (real) dev bazasida haqiqiy
    bot tokeni sozlangan bo'lsa, bu real, ~25s bloklovchi getUpdates so'rovini
    yuboradi. Testlar HECH QACHON real Telegramga chiqmasligi kerak (xuddi
    kamera bilan bir xil) — shuning uchun thread ishga tushirilishining o'zi
    har bir testda no-op qilinadi. Long-polling mantig'i (`bitta_tsikl`,
    `yangilanishni_qayta_ishla`) alohida, to'g'ridan-to'g'ri chaqirib
    (thread'siz) sinaladi — tests/test_telegram_polling.py."""
    monkeypatch.setattr("app.services.telegram_polling.ishga_tushir", lambda: None)
    monkeypatch.setattr("app.services.telegram_polling.toxtat", lambda: None)


def _test_database_url() -> str:
    berilgan = os.environ.get("TEST_DATABASE_URL")
    if berilgan:
        return berilgan
    qism = urlsplit(settings.DATABASE_URL)
    yangi_yol = qism.path.rstrip("/") + "_test"
    return urlunsplit((qism.scheme, qism.netloc, yangi_yol, qism.query, qism.fragment))


@pytest.fixture(scope="session")
def engine():
    url = _test_database_url()
    eng = create_engine(url)
    try:
        with eng.connect():
            pass
    except Exception as exc:
        pytest.skip(f"Test bazasiga ulanib bo'lmadi ({url}): {exc}. Avval shu nomda baza yarating yoki TEST_DATABASE_URL'ni sozlang.")

    Base.metadata.create_all(eng)
    yield eng
    Base.metadata.drop_all(eng)
    eng.dispose()


@pytest.fixture()
def db(engine):
    ulanish = engine.connect()
    tranzaksiya = ulanish.begin()
    Sessiya = sessionmaker(bind=ulanish)
    sessiya = Sessiya()
    yield sessiya
    sessiya.close()
    tranzaksiya.rollback()
    ulanish.close()


@pytest.fixture()
def client(db):
    def _get_db_override():
        yield db

    fastapi_app.dependency_overrides[get_db] = _get_db_override
    with TestClient(fastapi_app) as test_client:
        yield test_client
    fastapi_app.dependency_overrides.clear()


@pytest.fixture()
def admin(db) -> Foydalanuvchi:
    foydalanuvchi = Foydalanuvchi(
        ism="Test Admin", login="test_admin", parol_hash=parolni_hash("parol123"), rol=Rol.admin
    )
    db.add(foydalanuvchi)
    db.commit()
    db.refresh(foydalanuvchi)
    return foydalanuvchi


@pytest.fixture()
def admin_headers(admin: Foydalanuvchi) -> dict:
    token = token_yarat({"sub": str(admin.id), "rol": admin.rol.value, "smena": None})
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture()
def operator(db) -> Foydalanuvchi:
    foydalanuvchi = Foydalanuvchi(
        ism="Smena A", login="smena_a", parol_hash=parolni_hash("parolA"), rol=Rol.operator, smena=Smena.A
    )
    db.add(foydalanuvchi)
    db.commit()
    db.refresh(foydalanuvchi)
    return foydalanuvchi


@pytest.fixture()
def operator_headers(operator: Foydalanuvchi) -> dict:
    token = token_yarat({"sub": str(operator.id), "rol": operator.rol.value, "smena": operator.smena.value})
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture()
def mahsulot_tola(db) -> Mahsulot:
    mahsulot = Mahsulot(kod="tola", nomi="Tola")
    db.add(mahsulot)
    db.commit()
    db.refresh(mahsulot)
    return mahsulot


@pytest.fixture()
def stansiya(db) -> Stansiya:
    stansiya = Stansiya(nomi="Stansiya-1", rs232_port="COM3", rs232_baudrate=9600)
    db.add(stansiya)
    db.commit()
    db.refresh(stansiya)
    return stansiya

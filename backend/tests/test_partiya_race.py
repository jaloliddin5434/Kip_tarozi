"""3-QISM (audit topilmasi): `POST /partiyalar`da (`ochish_yoki_tanlash()`)
parallel-so'rov race condition — ikkita so'rov bir vaqtda aynan bir xil
(mahsulot, partiya_raqami) juftligini "ochish"ga urinsa, ikkinchisi
`uq_partiya_mahsulot_raqam` unique cheklovi tufayli `IntegrityError` olardi
va 500 qaytarardi. Endi bu holatni ushlab, QAYTA QIDIRIB, allaqachon
yaratilgan partiyani muvaffaqiyatli qaytarishi kerak.

MUHIM (test infratuzilmasi haqida): asosiy `db`/`client` fixture'lari BITTA
"flat" tranzaksiyaga bog'langan — `db.commit()` uni haqiqatan yopmaydi
(faqat flush), shuning uchun o'rtada bitta `db.rollback()` chaqirilsa HAM
o'sha tranzaksiya ichida OLDIN yaratilgan hamma narsa (masalan
`mahsulot_tola` fixture'i) HAM yo'qolib qoladi — bu shu fixture'ning ataylab
qilingan xususiyati (testlar orasida to'liq izolyatsiya uchun), lekin AYNAN
"rollback'dan keyin qayta qidirish" stsenariysini sinash uchun yaroqsiz.
Shuning uchun bu faylda ALOHIDA, HAQIQIY commit/rollback bilan ishlaydigan
kichik client tayyorlaymiz — o'zi yaratgan qatorlarni oxirida tozalaydi."""

import secrets

import pytest
from sqlalchemy import delete, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from starlette.testclient import TestClient

from app.core.database import get_db
from app.core.security import parolni_hash, token_yarat
from app.main import app as fastapi_app
from app.models.foydalanuvchi import Foydalanuvchi, Rol
from app.models.mahsulot import Mahsulot
from app.models.partiya import Partiya, PartiyaHolati


@pytest.fixture()
def haqiqiy_muhit(engine):
    """HAQIQIY (real) commit/rollback semantikasi bilan ishlaydigan mustaqil
    sessiya/client — asosiy `db`/`client` fixture'idan farqli o'laroq, bu
    yerda `db.rollback()` haqiqatan HAM shu so'rov ichida (hali committed
    bo'lmagan) narsalarnigina bekor qiladi, avvalgi committed ma'lumotlarga
    tegmaydi (aynan production'dagi kabi)."""
    tayyorlash = Session(bind=engine)
    tasodifiy = secrets.token_hex(4)
    mahsulot = Mahsulot(kod=f"race{tasodifiy}", nomi="Race Test Mahsulot")
    admin = Foydalanuvchi(ism="Race Test Admin", login=f"race_admin_{tasodifiy}", parol_hash=parolni_hash("x"), rol=Rol.admin)
    tayyorlash.add(mahsulot)
    tayyorlash.add(admin)
    tayyorlash.commit()
    tayyorlash.refresh(mahsulot)
    tayyorlash.refresh(admin)
    mahsulot_id, admin_id = mahsulot.id, admin.id
    token = token_yarat({"sub": str(admin.id), "rol": "admin", "smena": None, "tv": admin.token_versiyasi})
    tayyorlash.close()

    sorov_sessiyasi = Session(bind=engine)

    def _get_db_override():
        yield sorov_sessiyasi

    fastapi_app.dependency_overrides[get_db] = _get_db_override
    try:
        with TestClient(fastapi_app) as client:
            yield client, engine, mahsulot_id, {"Authorization": f"Bearer {token}"}
    finally:
        fastapi_app.dependency_overrides.clear()
        sorov_sessiyasi.close()
        tozalash = Session(bind=engine)
        try:
            tozalash.execute(delete(Partiya).where(Partiya.mahsulot_id == mahsulot_id))
            tozalash.execute(delete(Mahsulot).where(Mahsulot.id == mahsulot_id))
            tozalash.execute(delete(Foydalanuvchi).where(Foydalanuvchi.id == admin_id))
            tozalash.commit()
        finally:
            tozalash.close()


def _raqib_partiya_committed_yarat(engine, mahsulot_id: int, raqami: int, holati: PartiyaHolati) -> None:
    """"Parallel so'rov"ni simulyatsiya qiladi — MUSTAQIL ulanish orqali
    HAQIQIY committed qiladi (bizning so'rovimiz sessiyasidan butunlay
    mustaqil, xuddi haqiqiy ikkinchi worker/instance kabi)."""
    mustaqil = Session(bind=engine)
    try:
        mustaqil.add(Partiya(mahsulot_id=mahsulot_id, partiya_raqami=raqami, holati=holati))
        mustaqil.commit()
    finally:
        mustaqil.close()


def _mahsulot_kodini_ol(engine, mahsulot_id: int) -> str:
    sess = Session(bind=engine)
    try:
        return sess.get(Mahsulot, mahsulot_id).kod
    finally:
        sess.close()


def _sorov_sessiyasini_ol():
    """`get_db` override'i chaqirilganda qaytariladigan (route ichida
    haqiqatan ishlatiladigan) sessiyani oladi — uning `commit` metodini
    monkeypatch qilish uchun."""
    return next(fastapi_app.dependency_overrides[get_db]())


def test_parallel_partiya_ochish_integrity_error_dan_keyin_mavjudini_qaytaradi(haqiqiy_muhit, monkeypatch):
    client, engine, mahsulot_id, headers = haqiqiy_muhit
    mahsulot_kodi = _mahsulot_kodini_ol(engine, mahsulot_id)

    # Route ichida ishlatiladigan sessiyani topamiz — uning `commit`
    # metodini birinchi chaqiruvda IntegrityError bilan yiqiladigan qilib
    # almashtiramiz.
    db = _sorov_sessiyasini_ol()
    haqiqiy_commit = db.commit
    holat = {"birinchi": True}

    def soxta_commit():
        if holat["birinchi"]:
            holat["birinchi"] = False
            # "Raqib" so'rov bizdan OLDIN, MUSTAQIL ulanish orqali, aynan shu
            # (mahsulot, raqam)ni HAQIQATAN committed qilib ulgurdi.
            _raqib_partiya_committed_yarat(engine, mahsulot_id, 888, PartiyaHolati.ochiq)
            raise IntegrityError(
                "INSERT INTO partiyalar ...", {}, Exception("duplicate key value violates unique constraint")
            )
        return haqiqiy_commit()

    monkeypatch.setattr(db, "commit", soxta_commit)

    javob = client.post(
        "/api/v1/partiyalar",
        json={"mahsulot_kodi": mahsulot_kodi, "partiya_raqami": 888},
        headers=headers,
    )

    assert javob.status_code == 200, javob.text
    assert javob.json()["partiya_raqami"] == 888
    assert javob.json()["holati"] == "ochiq"

    tekshiruvchi = Session(bind=engine)
    try:
        soni = tekshiruvchi.execute(
            select(func.count())
            .select_from(Partiya)
            .where(Partiya.mahsulot_id == mahsulot_id, Partiya.partiya_raqami == 888)
        ).scalar_one()
        assert soni == 1, "dublikat partiya yaratilmagan bo'lishi kerak"
    finally:
        tekshiruvchi.close()


def test_parallel_partiya_ochish_raqib_yopiq_bolsa_400_qaytaradi(haqiqiy_muhit, monkeypatch):
    """Race paytida "raqib" allaqachon partiyani yopib/sotib ulgurgan bo'lsa —
    bizning so'rovimiz baribir 400 (mavjud "partiya band" xatosi) qaytarishi
    kerak, 200 emas (500 esa hech qachon emas)."""
    client, engine, mahsulot_id, headers = haqiqiy_muhit
    mahsulot_kodi = _mahsulot_kodini_ol(engine, mahsulot_id)
    db = _sorov_sessiyasini_ol()
    haqiqiy_commit = db.commit
    holat = {"birinchi": True}

    def soxta_commit():
        if holat["birinchi"]:
            holat["birinchi"] = False
            _raqib_partiya_committed_yarat(engine, mahsulot_id, 889, PartiyaHolati.yopiq)
            raise IntegrityError("INSERT INTO partiyalar ...", {}, Exception("duplicate key"))
        return haqiqiy_commit()

    monkeypatch.setattr(db, "commit", soxta_commit)

    javob = client.post(
        "/api/v1/partiyalar",
        json={"mahsulot_kodi": mahsulot_kodi, "partiya_raqami": 889},
        headers=headers,
    )

    assert javob.status_code == 400, javob.text
    assert "yopiq" in javob.json()["detail"].lower()

import asyncio
import sys
import threading
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

import pytest

from app.core.config import settings
from app.models.partiya import Partiya, PartiyaHolati
from app.services.hujjatlar.nakladnoy import nakladnoy_pdf_yarat


def _sotilgan_partiya(client, operator_headers, admin_headers, partiya_raqami: int) -> dict:
    partiya = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": partiya_raqami}, headers=operator_headers
    ).json()

    for ogirlik in (150.0, 148.5):
        client.post(
            "/api/v1/kiplar",
            json={
                "mijoz_id": str(uuid4()),
                "partiya_id": partiya["id"],
                "ogirlik": ogirlik,
                "mahalliy_vaqt": datetime.now(timezone.utc).isoformat(),
            },
            headers=operator_headers,
        )

    yopish = client.patch(f"/api/v1/partiyalar/{partiya['id']}/yopish", headers=operator_headers)
    assert yopish.status_code == 200

    sotish = client.post(
        f"/api/v1/partiyalar/{partiya['id']}/sotish",
        json={
            "sotuv_sanasi": "2026-08-19",
            "xaridor": "Sinov Xaridor MChJ",
            "dogovor_raqami": "DOG-TEST-1",
            "sort": "1-sort",
            "urama_bilan_vazn": 305.4,
            "urama_vazni": 5.4,
            "sof_vazn": 300.0,
            "kondicion_vazni": 298.5,
        },
        headers=admin_headers,
    )
    assert sotish.status_code == 200
    return sotish.json()


def test_sotilganda_nakladnoy_pdf_haqiqatan_yaratiladi(client, operator_headers, admin_headers, mahsulot_tola):
    tana = _sotilgan_partiya(client, operator_headers, admin_headers, 900)

    assert tana["nakladnoy_raqami"] is not None
    assert tana["nakladnoy_pdf_yoli"] is not None

    fayl_yoli = Path(settings.STORAGE_PATH) / tana["nakladnoy_pdf_yoli"]
    try:
        assert fayl_yoli.is_file()
        assert fayl_yoli.stat().st_size > 0
        assert fayl_yoli.read_bytes()[:4] == b"%PDF"
    finally:
        fayl_yoli.unlink(missing_ok=True)


def test_nakladnoy_endpoint_faylni_qaytaradi(client, operator_headers, admin_headers, mahsulot_tola):
    tana = _sotilgan_partiya(client, operator_headers, admin_headers, 901)

    try:
        javob = client.get(f"/api/v1/partiyalar/{tana['id']}/nakladnoy", headers=admin_headers)
        assert javob.status_code == 200
        assert javob.headers["content-type"] == "application/pdf"
        assert len(javob.content) > 0
        assert javob.content[:4] == b"%PDF"
    finally:
        Path(settings.STORAGE_PATH, tana["nakladnoy_pdf_yoli"]).unlink(missing_ok=True)


def test_nakladnoy_endpoint_operatorga_yopiq(client, operator_headers, admin_headers, mahsulot_tola):
    tana = _sotilgan_partiya(client, operator_headers, admin_headers, 902)

    try:
        javob = client.get(f"/api/v1/partiyalar/{tana['id']}/nakladnoy", headers=operator_headers)
        assert javob.status_code == 403
    finally:
        Path(settings.STORAGE_PATH, tana["nakladnoy_pdf_yoli"]).unlink(missing_ok=True)


def test_nakladnoy_hali_yoq_boisa_404(client, operator_headers, admin_headers, mahsulot_tola):
    partiya = client.post(
        "/api/v1/partiyalar", json={"mahsulot_kodi": "tola", "partiya_raqami": 903}, headers=operator_headers
    ).json()

    javob = client.get(f"/api/v1/partiyalar/{partiya['id']}/nakladnoy", headers=admin_headers)
    assert javob.status_code == 404


@pytest.mark.skipif(sys.platform != "win32", reason="Bu tuzatish faqat Windows'ga xos")
def test_selector_siyosati_faol_bolsada_pdf_yaratiladi(client, operator_headers, admin_headers, mahsulot_tola):
    """Real serverda uchragan xatoni takrorlaydi: agar joriy event loop
    siyosati (Proactor emas) Selector bo'lsa, FastAPI'ning threadpool ishchi
    oqimida Playwright brauzer subprocessini ishga tushira olmay
    NotImplementedError otar edi. nakladnoy_pdf_yarat endi shu holatda ham
    o'zi Proactor'ga o'tkazib, PDF'ni muvaffaqiyatli yaratishi kerak."""
    eski_siyosat = asyncio.get_event_loop_policy()
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
    try:
        tana = _sotilgan_partiya(client, operator_headers, admin_headers, 904)
        assert tana["nakladnoy_pdf_yoli"] is not None

        fayl_yoli = Path(settings.STORAGE_PATH) / tana["nakladnoy_pdf_yoli"]
        try:
            assert fayl_yoli.is_file()
            assert fayl_yoli.stat().st_size > 0
            assert fayl_yoli.read_bytes()[:4] == b"%PDF"
        finally:
            fayl_yoli.unlink(missing_ok=True)
    finally:
        asyncio.set_event_loop_policy(eski_siyosat)


def test_parallel_sotish_pdf_generatsiyasida_race_condition_bolmaydi():
    """nakladnoy_pdf_yarat() ichidagi asyncio event loop siyosati JARAYON
    darajasida umumiy global holat edi — bir nechta savdo bir vaqtda PDF
    generatsiya qilsa, ular bir-biriga xalaqit berishi mumkin edi. Bu test
    bir nechta partiyani BIR VAQTDA (haqiqiy parallel thread'lardan) PDF
    generatsiya qilishga majburlab, hech biri xato bermasligini va har
    birining o'z, to'g'ri PDF fayli borligini tasdiqlaydi.

    HTTP/DB qatlamidan o'tmasdan, to'g'ridan-to'g'ri nakladnoy_pdf_yarat()ni
    chaqiradi — conftest.py'dagi `client` fixture barcha so'rovlar uchun
    BITTA umumiy SQLAlchemy sessiyasini ishlatadi, u o'zi thread-safe emas,
    shuning uchun haqiqiy parallel HTTP so'rovlari shu (nakladnoy.py'ga
    aloqasi bo'lmagan) sabab bilan risolat qilinardi."""
    eski_siyosat_testdan_oldin = asyncio.get_event_loop_policy()

    natijalar: dict[int, str | None] = {}
    xatolar: list[BaseException] = []
    natija_qulfi = threading.Lock()

    def ishla(i: int) -> None:
        partiya = Partiya(
            id=2000 + i,
            mahsulot_id=1,
            partiya_raqami=970 + i,
            holati=PartiyaHolati.sotilgan,
            nakladnoy_raqami=f"NK-RACE-TEST-{i}",
            sotuv_sanasi=None,
            xaridor=f"Sinov Xaridor {i}",
            dogovor_raqami=None,
            sort=None,
            urama_bilan_vazn=100.0 + i,
            urama_vazni=5.0,
            sof_vazn=95.0 + i,
            kondicion_vazni=94.0 + i,
        )
        try:
            natija = nakladnoy_pdf_yarat(partiya, "Tola", 5)
        except BaseException as e:  # noqa: BLE001 — testda har qanday xatoni tutib, keyin bitta joyda tasdiqlaymiz
            with natija_qulfi:
                xatolar.append(e)
            return
        with natija_qulfi:
            natijalar[i] = natija

    soni = 4
    threadlar = [threading.Thread(target=ishla, args=(i,)) for i in range(soni)]
    for t in threadlar:
        t.start()
    for t in threadlar:
        t.join(timeout=60)

    try:
        assert not xatolar, f"Parallel PDF generatsiyasida xato(lar) yuz berdi: {xatolar}"
        assert len(natijalar) == soni

        fayllar = []
        for i in range(soni):
            yoli = natijalar[i]
            assert yoli is not None
            fayl = Path(settings.STORAGE_PATH) / yoli
            fayllar.append(fayl)
            assert fayl.is_file(), f"#{i} uchun PDF fayl topilmadi: {fayl}"
            assert fayl.stat().st_size > 0
            assert fayl.read_bytes()[:4] == b"%PDF"

        # Har bir chaqiruv o'z, ALOHIDA faylini yaratgan bo'lishi kerak —
        # birontasi boshqasining ustidan yozib yubormagan.
        assert len({f.resolve() for f in fayllar}) == soni
    finally:
        for i in range(soni):
            yoli = natijalar.get(i)
            if yoli:
                (Path(settings.STORAGE_PATH) / yoli).unlink(missing_ok=True)

    # Global event loop siyosati testdan OLDINGI holatiga qaytgan bo'lishi
    # kerak — bir nechta parallel chaqiruvdan keyin ham "chala" holatda
    # qolib ketmasligi kerak.
    assert asyncio.get_event_loop_policy() is eski_siyosat_testdan_oldin

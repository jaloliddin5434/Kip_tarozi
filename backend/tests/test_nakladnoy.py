import asyncio
import sys
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

import pytest

from app.core.config import settings


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

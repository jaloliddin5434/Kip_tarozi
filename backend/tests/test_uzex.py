"""UZEX narx integratsiyasi — barcha testlar mocklangan (tarmoqsiz)."""

from datetime import datetime, timedelta, timezone

import httpx
import pytest

from app.services import uzex

# uzex.uz/Quote/GetQuotes javobiga o'xshash namuna (qisqartirilgan)
_NAMUNA_JSON = [
    {"name": "Avtobenzin A-92", "summa": "13 297 249.70", "difference": "0", "percent": "0", "tovarNum": 0},
    {"name": "Paxta tola 1 nav 4 tip (oliy) 2025-yil hosili", "summa": "20 222 078.05",
     "difference": "-34 452.86", "percent": "0.17", "tovarNum": 0},
    {"name": "Tozalangan dezodoratsiyalangan ekstraktsiyalangan paxta yog'i presslangan 1-nav",
     "summa": "15 000 000.00", "difference": "0", "percent": "0", "tovarNum": 0},
    {"name": "Paxta chigiti shroti", "summa": "5 412 735.85", "difference": "0", "percent": "0", "tovarNum": 0},
]


class _SoxtaJavob:
    def __init__(self, data, status_code=200):
        self._data = data
        self.status_code = status_code

    def raise_for_status(self):
        if self.status_code >= 400:
            raise httpx.HTTPError(f"HTTP {self.status_code}")

    def json(self):
        return self._data


@pytest.fixture(autouse=True)
def _keshni_tozalash():
    uzex.keshni_tozalash()
    yield
    uzex.keshni_tozalash()


def _mock_get(monkeypatch, data=None, exc=None):
    def _get(*args, **kwargs):
        if exc is not None:
            raise exc
        return _SoxtaJavob(data)
    monkeypatch.setattr(uzex.httpx, "get", _get)


# --- sof mantiq testlari ---

def test_sonni_ajrat_turli_formatlar():
    assert uzex._sonni_ajrat("20 222 078.05") == 20222078.05
    assert uzex._sonni_ajrat("13 984 068,00") == 13984068.0
    assert uzex._sonni_ajrat("1\xa0501\xa0000") == 1501000.0
    assert uzex._sonni_ajrat("") is None
    assert uzex._sonni_ajrat("—") is None
    assert uzex._sonni_ajrat("0") is None  # 0 va manfiy — yaroqsiz


def test_json_dan_narxlar_tola_ni_ajratadi_va_kg_ga_otkazadi():
    narxlar = uzex._json_dan_narxlar(_NAMUNA_JSON)
    # 20 222 078.05 so'm/tonna -> 20222.08 so'm/kg
    assert narxlar == {"tola": 20222.08}
    # "paxta yog'i" va "chigiti shroti" — tola emas, chiqmasligi kerak
    assert "lint" not in narxlar


def test_json_dan_narxlar_bir_nechta_tola_qatorini_ortalaydi():
    js = [
        {"name": "Paxta tola 1 nav 4 tip (oliy) 2025-yil hosili", "summa": "20 000 000"},
        {"name": "Paxta tola 2 nav 4 tip (o'rta) 2025-yil hosili", "summa": "18 000 000"},
    ]
    assert uzex._json_dan_narxlar(js) == {"tola": 19000.0}


def test_json_dan_narxlar_lint_pux_ulyuk_mos_keladi():
    js = [
        {"name": "Lint 1 nav tip B ( klass oliy)", "summa": "5 388 483.76"},
        {"name": "Paxta momig‘i", "summa": "1 501 000"},
        {"name": "O‘lik paxta, paxta  tolasining chiqindilari", "summa": "1 538 121.42"},
    ]
    natija = uzex._json_dan_narxlar(js)
    assert natija["lint"] == 5388.48
    assert natija["pux"] == 1501.0
    assert natija["ulyuk"] == 1538.12


def test_json_dan_narxlar_momiq_chiqindisi_pux_emas():
    js = [{"name": "Paxta momig‘i chiqindisi", "summa": "963 363.52"}]
    assert uzex._json_dan_narxlar(js) == {}


# --- uzex_narxlari(): kesh, degradatsiya ---

def test_uzex_narxlari_real_qiymat_tola_uchun_stub_qolganlar_uchun(monkeypatch):
    _mock_get(monkeypatch, data=_NAMUNA_JSON)
    narxlar, vaqt = uzex.uzex_narxlari()
    xarita = {kod: narx for kod, _, narx in narxlar}
    assert xarita["tola"] == 20222.08                # UZEX'dan
    assert xarita["lint"] == 12_000.0                # stub (topilmadi)
    assert xarita["pux"] == 6_500.0
    assert xarita["ulyuk"] == 4_000.0
    assert [k for k, _, _ in narxlar] == ["tola", "lint", "pux", "ulyuk"]
    assert (datetime.now(timezone.utc) - vaqt).total_seconds() < 5


def test_uzex_narxlari_tarmoq_xatosida_stubga_qaytadi(monkeypatch):
    _mock_get(monkeypatch, exc=httpx.ConnectError("ulanib bo'lmadi"))
    narxlar, vaqt = uzex.uzex_narxlari()
    assert [(k, n, x) for k, n, x in narxlar] == list(uzex.STUB_NARXLAR)


def test_uzex_narxlari_kutilmagan_json_stubga_qaytadi(monkeypatch):
    _mock_get(monkeypatch, data={"xato": "struktura"})  # ro'yxat emas
    narxlar, _ = uzex.uzex_narxlari()
    assert [(k, n, x) for k, n, x in narxlar] == list(uzex.STUB_NARXLAR)


def test_uzex_narxlari_paxta_topilmasa_stubga_qaytadi(monkeypatch):
    _mock_get(monkeypatch, data=[{"name": "Avtobenzin A-92", "summa": "13 000 000"}])
    narxlar, _ = uzex.uzex_narxlari()
    assert [(k, n, x) for k, n, x in narxlar] == list(uzex.STUB_NARXLAR)


def test_uzex_narxlari_kesh_bir_soat_ichida_qayta_sorov_yubormaydi(monkeypatch):
    chaqiruvlar = {"soni": 0}

    def _get(*a, **k):
        chaqiruvlar["soni"] += 1
        return _SoxtaJavob(_NAMUNA_JSON)

    monkeypatch.setattr(uzex.httpx, "get", _get)
    _, vaqt1 = uzex.uzex_narxlari()
    _, vaqt2 = uzex.uzex_narxlari()
    assert chaqiruvlar["soni"] == 1        # ikkinchisi keshdan
    assert vaqt1 == vaqt2


def test_uzex_narxlari_kesh_eskirsa_lekin_sorov_uzilsa_eski_qiymat(monkeypatch):
    _mock_get(monkeypatch, data=_NAMUNA_JSON)
    narxlar1, vaqt1 = uzex.uzex_narxlari()

    # keshni 2 soat oldingi qilib "eskiraytiramiz"
    uzex._kesh["vaqt"] = vaqt1 - timedelta(hours=2)
    _mock_get(monkeypatch, exc=httpx.ConnectTimeout("timeout"))

    narxlar2, vaqt2 = uzex.uzex_narxlari()
    assert narxlar2 == narxlar1                 # eski (real) kesh, stub emas
    assert vaqt2 == vaqt1 - timedelta(hours=2)  # haqiqiy oxirgi muvaffaqiyat vaqti


# --- endpoint ---

def test_uzex_narxlar_endpoint_javob_strukturasi_ozgarmagan(client, admin_headers, monkeypatch):
    _mock_get(monkeypatch, data=_NAMUNA_JSON)
    client.post("/api/v1/moliyaviy/parolni-ornatish", json={"parol": "maxfiy1234"}, headers=admin_headers)
    token = client.post(
        "/api/v1/moliyaviy/kirish", json={"parol": "maxfiy1234"}, headers=admin_headers
    ).json()["access_token"]
    mh = {"Authorization": f"Bearer {token}"}

    javob = client.get("/api/v1/moliyaviy/uzex-narxlar", headers=mh)
    assert javob.status_code == 200
    tana = javob.json()
    assert len(tana) == 4
    tola = next(r for r in tana if r["mahsulot_kodi"] == "tola")
    assert set(tola) == {"mahsulot_kodi", "mahsulot_nomi", "narx_som", "yangilangan_vaqt"}
    assert tola["narx_som"] == 20222.08
    assert tola["mahsulot_nomi"] == "Tola"
    # yangilangan_vaqt — ISO datetime, parslanadi
    datetime.fromisoformat(tola["yangilangan_vaqt"])

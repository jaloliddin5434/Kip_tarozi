"""`smena_mahsulot_jadval()` — vizual formatlash: sarlavha (qalin + mahsulotga
xos rang), chegaralar, avtomoslashuvchi ustun kengliklari, "Operator" ustuni,
va "JAMI" qatori (qalin + sarlavhadan farqli, lekin bir xil rang oilasidagi
fon). Bu funksiya UCH joyda ishlatiladi (`/hisobotlar/smena-mahsulot-excel`,
`/hisobotlar/smena-excel` -> ZIP, `scripts/backup_tuzilma.py`) — shuning
uchun to'g'ridan-to'g'ri o'zida sinaladi, HTTP orqali emas."""

import uuid
from datetime import date, datetime, timezone

import pytest

from app.models.foydalanuvchi import Smena
from app.models.mahsulot import Mahsulot
from app.models.partiya import Partiya, PartiyaHolati
from app.models.kip import Kip, KipHolati
from app.services.hisobotlar_excel import _MAHSULOT_RANGLARI, smena_mahsulot_jadval


def _partiya_yarat(db, mahsulot_id, raqami):
    partiya = Partiya(mahsulot_id=mahsulot_id, partiya_raqami=raqami, holati=PartiyaHolati.ochiq)
    db.add(partiya)
    db.commit()
    db.refresh(partiya)
    return partiya


def _kip_yarat(db, partiya_id, kip_raqami, ogirlik, smena, operator_id, sana: date | None = None):
    vaqt = datetime.now(timezone.utc) if sana is None else datetime(sana.year, sana.month, sana.day, 10, 0, tzinfo=timezone.utc)
    kip = Kip(
        mijoz_id=str(uuid.uuid4()),
        partiya_id=partiya_id,
        kip_raqami=kip_raqami,
        ogirlik=ogirlik,
        smena=smena,
        operator_id=operator_id,
        mahalliy_vaqt=vaqt,
        vaqt=vaqt,
        holati=KipHolati.aktiv,
    )
    db.add(kip)
    db.commit()
    return kip


@pytest.fixture()
def mahsulotlar(db, mahsulot_tola):
    lint = Mahsulot(kod="lint", nomi="Lint")
    pux = Mahsulot(kod="pux", nomi="Pux")
    ulyuk = Mahsulot(kod="ulyuk", nomi="Ulyuk")
    db.add_all([lint, pux, ulyuk])
    db.commit()
    for m in (lint, pux, ulyuk):
        db.refresh(m)
    return {"tola": mahsulot_tola, "lint": lint, "pux": pux, "ulyuk": ulyuk}


HUJAYRA_USTUNLARI = ["A", "B", "C", "D", "E"]


@pytest.mark.parametrize("kod", ["tola", "lint", "pux", "ulyuk"])
def test_sarlavha_mahsulotga_xos_rangda_va_qalin(db, operator, mahsulotlar, kod):
    mahsulot = mahsulotlar[kod]
    sana = date.today()
    partiya = _partiya_yarat(db, mahsulot.id, 9500 + hash(kod) % 100)
    _kip_yarat(db, partiya.id, 1, 100.0, Smena.A, operator.id, sana)

    wb = smena_mahsulot_jadval(db, sana, Smena.A, mahsulot)
    ws = wb.active

    kutilgan = _MAHSULOT_RANGLARI[kod]
    sarlavha_qatori = 3  # 1=sarlavha matni, 2=bo'sh, 3=ustun sarlavhalari
    for ustun in HUJAYRA_USTUNLARI:
        hujayra = ws[f"{ustun}{sarlavha_qatori}"]
        assert hujayra.font.bold is True, f"{ustun}{sarlavha_qatori} qalin bo'lishi kerak"
        assert hujayra.font.color.rgb.endswith(kutilgan["toq"]), f"{ustun}{sarlavha_qatori} matn rangi noto'g'ri"
        assert hujayra.fill.fgColor.rgb.endswith(kutilgan["och"]), f"{ustun}{sarlavha_qatori} fon rangi noto'g'ri"

    # Ustun sarlavhalari — "Operator" ustuni ENDI mavjud.
    matnlar = [ws[f"{u}{sarlavha_qatori}"].value for u in HUJAYRA_USTUNLARI]
    assert matnlar == ["Kip №", "Partiya №", "Vaqt", "Og'irlik, kg", "Operator"]


def test_turli_mahsulotlar_rangi_bir_biridan_farq_qiladi():
    """4 mahsulotning har biri boshqacha rangda bo'lishi shart — bittasi
    ikkinchisiga o'xshab qolmasin."""
    toq_ranglar = {kod: qiymat["toq"] for kod, qiymat in _MAHSULOT_RANGLARI.items()}
    och_ranglar = {kod: qiymat["och"] for kod, qiymat in _MAHSULOT_RANGLARI.items()}
    assert len(set(toq_ranglar.values())) == 4
    assert len(set(och_ranglar.values())) == 4


def test_jami_qatori_qalin_va_sarlavhadan_farqli_fon(db, operator, mahsulot_tola):
    sana = date.today()
    partiya = _partiya_yarat(db, mahsulot_tola.id, 9600)
    _kip_yarat(db, partiya.id, 1, 100.0, Smena.A, operator.id, sana)
    _kip_yarat(db, partiya.id, 2, 50.0, Smena.A, operator.id, sana)

    wb = smena_mahsulot_jadval(db, sana, Smena.A, mahsulot_tola)
    ws = wb.active

    jami_qatori = ws.max_row
    assert str(ws[f"A{jami_qatori}"].value).startswith("JAMI")

    kutilgan = _MAHSULOT_RANGLARI["tola"]
    for ustun in HUJAYRA_USTUNLARI:
        hujayra = ws[f"{ustun}{jami_qatori}"]
        assert hujayra.font.bold is True
        assert hujayra.fill.fgColor.rgb.endswith(kutilgan["jami"])

    # JAMI foni sarlavha fonidan ANIQ farq qiladi (bir xil rang oilasida bo'lsa ham).
    assert kutilgan["jami"] != kutilgan["och"]
    assert ws["D" + str(jami_qatori)].value == 150.0


def test_barcha_hujayralar_chegaralangan(db, operator, mahsulot_tola):
    sana = date.today()
    partiya = _partiya_yarat(db, mahsulot_tola.id, 9601)
    _kip_yarat(db, partiya.id, 1, 100.0, Smena.A, operator.id, sana)

    wb = smena_mahsulot_jadval(db, sana, Smena.A, mahsulot_tola)
    ws = wb.active

    # Sarlavha qatoridan (3) oxirigacha (JAMI) — har bir katakchada chegara bo'lishi kerak.
    for qator in ws.iter_rows(min_row=3, max_row=ws.max_row, max_col=5):
        for hujayra in qator:
            assert hujayra.border.left.style == "thin"
            assert hujayra.border.right.style == "thin"
            assert hujayra.border.top.style == "thin"
            assert hujayra.border.bottom.style == "thin"

    # Sarlavhadan OLDINGI qatorlar (sarlavha matni, bo'sh qator) chegaralanmagan.
    assert ws["A1"].border.left.style is None


def test_operator_ustuni_togri_ismni_korsatadi(db, mahsulot_tola):
    from app.core.security import parolni_hash
    from app.models.foydalanuvchi import Foydalanuvchi, Rol

    op_a = Foydalanuvchi(ism="Aziz Aliyev", login="op_excel_a", parol_hash=parolni_hash("p1"), rol=Rol.operator, smena=Smena.A)
    op_a2 = Foydalanuvchi(ism="Botir Karimov", login="op_excel_a2", parol_hash=parolni_hash("p2"), rol=Rol.operator, smena=Smena.A)
    db.add_all([op_a, op_a2])
    db.commit()
    db.refresh(op_a)
    db.refresh(op_a2)

    sana = date.today()
    partiya = _partiya_yarat(db, mahsulot_tola.id, 9602)
    _kip_yarat(db, partiya.id, 1, 100.0, Smena.A, op_a.id, sana)
    _kip_yarat(db, partiya.id, 2, 105.0, Smena.A, op_a2.id, sana)

    wb = smena_mahsulot_jadval(db, sana, Smena.A, mahsulot_tola)
    ws = wb.active

    qatorlar = [r for r in ws.iter_rows(values_only=True) if isinstance(r[0], int)]
    assert qatorlar[0][4] == "Aziz Aliyev"
    assert qatorlar[1][4] == "Botir Karimov"


def test_ustun_kengliklari_kamida_minimal_va_uzun_matn_uchun_kengayadi(db, mahsulot_tola):
    from app.core.security import parolni_hash
    from app.models.foydalanuvchi import Foydalanuvchi, Rol

    uzun_ismli_operator = Foydalanuvchi(
        ism="Abdurahmonova Zilola Botirovna",  # 30 belgi — 18 minimal kenglikdan uzunroq
        login="op_excel_uzun",
        parol_hash=parolni_hash("p1"),
        rol=Rol.operator,
        smena=Smena.A,
    )
    db.add(uzun_ismli_operator)
    db.commit()
    db.refresh(uzun_ismli_operator)

    sana = date.today()
    partiya = _partiya_yarat(db, mahsulot_tola.id, 9603)
    _kip_yarat(db, partiya.id, 1, 100.0, Smena.A, uzun_ismli_operator.id, sana)

    wb = smena_mahsulot_jadval(db, sana, Smena.A, mahsulot_tola)
    ws = wb.active

    kengliklar = {u: ws.column_dimensions[u].width for u in HUJAYRA_USTUNLARI}
    # Minimal kengliklardan TORROQ hech biri bo'lmasligi kerak.
    for kenglik, minimal in zip(kengliklar.values(), [10, 12, 12, 14, 18]):
        assert kenglik >= minimal

    # Operator ustuni (E) — ism uzunligi (30) minimal (18)dan kattaroq bo'lgani
    # uchun AVTOMATIK kengaygan bo'lishi kerak.
    assert kengliklar["E"] > 18


def test_qisqa_malumot_bolsa_ustun_minimal_kenglikda_qoladi(db, operator, mahsulot_tola):
    sana = date.today()
    partiya = _partiya_yarat(db, mahsulot_tola.id, 9604)
    _kip_yarat(db, partiya.id, 1, 100.0, Smena.A, operator.id, sana)

    wb = smena_mahsulot_jadval(db, sana, Smena.A, mahsulot_tola)
    ws = wb.active

    # "Vaqt" ustuni (C) — sarlavha (4 belgi) ham, "HH:MM:SS" qiymati (8 belgi)
    # ham, JAMI qatoridagi bo'sh katakcha ham minimal (12) dan qisqa — ustun
    # baribir 12dan tor bo'lmasligi, lekin ortiqcha ham kengaymasligi kerak.
    assert ws.column_dimensions["C"].width == 12

    # "Kip №" ustuni (A) esa — JAMI qatoridagi "JAMI (1 kip)" matni (12 belgi)
    # minimal (10) dan uzunroq bo'lgani uchun AVTOMATIK kengaygan bo'lishi kerak.
    assert ws.column_dimensions["A"].width == len("JAMI (1 kip)") + 2

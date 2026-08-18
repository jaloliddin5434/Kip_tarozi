import uuid
from datetime import date, datetime, timezone
from io import BytesIO

from openpyxl import load_workbook

from app.core.security import parolni_hash, token_yarat
from app.models.foydalanuvchi import Foydalanuvchi, Rol, Smena
from app.models.kip import Kip, KipHolati
from app.models.mahsulot import Mahsulot
from app.models.partiya import Partiya, PartiyaHolati


def _partiya_yarat(db, mahsulot_id, raqami):
    partiya = Partiya(mahsulot_id=mahsulot_id, partiya_raqami=raqami, holati=PartiyaHolati.ochiq)
    db.add(partiya)
    db.commit()
    db.refresh(partiya)
    return partiya


def _kip_yarat(db, partiya_id, kip_raqami, ogirlik, smena, sana: date, operator_id):
    vaqt = datetime(sana.year, sana.month, sana.day, 10, 0, tzinfo=timezone.utc)
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


def test_smena_excel_admin_togri_malumot_bilan_generatsiya_qiladi(client, db, admin_headers, operator, mahsulot_tola):
    lint = Mahsulot(kod="lint", nomi="Lint")
    pux = Mahsulot(kod="pux", nomi="Pux")
    ulyuk = Mahsulot(kod="ulyuk", nomi="Ulyuk")
    db.add_all([lint, pux, ulyuk])
    db.commit()

    sana = date.today()
    tola_partiya = _partiya_yarat(db, mahsulot_tola.id, 900)
    lint_partiya = _partiya_yarat(db, lint.id, 901)

    _kip_yarat(db, tola_partiya.id, 1, 100.0, Smena.A, sana, operator.id)
    _kip_yarat(db, tola_partiya.id, 2, 110.0, Smena.A, sana, operator.id)
    _kip_yarat(db, lint_partiya.id, 1, 50.0, Smena.A, sana, operator.id)
    # boshqa smena — hisobotga kirmasligi kerak
    _kip_yarat(db, tola_partiya.id, 3, 999.0, Smena.B, sana, operator.id)

    javob = client.get(
        "/api/v1/hisobotlar/smena-excel", params={"sana": sana.isoformat(), "smena": "A"}, headers=admin_headers
    )
    assert javob.status_code == 200
    assert javob.headers["content-type"] == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    assert f"Smena_A_{sana.isoformat()}.xlsx" in javob.headers["content-disposition"]

    wb = load_workbook(BytesIO(javob.content))
    ws = wb.active

    qatorlar = {row[0].value: row for row in ws.iter_rows(min_row=2)}

    tola_qatori = qatorlar["Tola"]
    assert tola_qatori[1].value == 2
    assert tola_qatori[2].value == 210.0
    assert tola_qatori[3].value == 105.0

    lint_qatori = qatorlar["Lint"]
    assert lint_qatori[1].value == 1
    assert lint_qatori[2].value == 50.0
    assert lint_qatori[3].value == 50.0

    pux_qatori = qatorlar["Pux"]
    assert pux_qatori[1].value == 0
    assert pux_qatori[2].value == 0.0

    jami_qatori = qatorlar["JAMI"]
    assert jami_qatori[1].value == 3
    assert jami_qatori[2].value == 260.0


def test_smena_excel_operator_oz_smenasini_olishi_mumkin(client, operator_headers, operator):
    javob = client.get(
        "/api/v1/hisobotlar/smena-excel",
        params={"sana": date.today().isoformat(), "smena": operator.smena.value},
        headers=operator_headers,
    )
    assert javob.status_code == 200


def test_smena_excel_operator_boshqa_smenani_olalmaydi(client, operator_headers):
    javob = client.get(
        "/api/v1/hisobotlar/smena-excel",
        params={"sana": date.today().isoformat(), "smena": "B"},
        headers=operator_headers,
    )
    assert javob.status_code == 403


def test_smena_excel_tokensiz_kira_olmaydi(client):
    javob = client.get("/api/v1/hisobotlar/smena-excel", params={"sana": date.today().isoformat(), "smena": "A"})
    assert javob.status_code == 401


def test_smena_excel_boshqa_rol_kira_olmaydi(client, db):
    foydalanuvchi = Foydalanuvchi(
        ism="Tayyor Test",
        login="tayyor_hisobot_test",
        parol_hash=parolni_hash("parolT"),
        rol=Rol.tayyor_mahsulotlar,
    )
    db.add(foydalanuvchi)
    db.commit()
    db.refresh(foydalanuvchi)

    token = token_yarat({"sub": str(foydalanuvchi.id), "rol": "tayyor_mahsulotlar", "smena": None})
    headers = {"Authorization": f"Bearer {token}"}

    javob = client.get(
        "/api/v1/hisobotlar/smena-excel", params={"sana": date.today().isoformat(), "smena": "A"}, headers=headers
    )
    assert javob.status_code == 403

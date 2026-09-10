"""Telegram getUpdates long-polling — callback_query (inline tugma) qayta
ishlash. Hech bir test real Telegramga chiqmaydi: httpx.get/post har doim
mocklanadi (loyihadagi yagona uslub — test_telegram_surat.py/test_uzex.py
bilan bir xil, monkeypatch.setattr orqali)."""

import uuid
from datetime import datetime, timezone

import httpx
import pytest

from app.models.kamera_tasdiq import KameraTasdiqHolati, KameraTasdiqSorovi
from app.models.kip import Kip
from app.models.kip_togrilash import KipTogrilashHolati, KipTogrilashZayavkasi
from app.models.mahsulot import Mahsulot
from app.models.partiya import Partiya, PartiyaHolati
from app.models.sozlama import Sozlama
from app.services import telegram_polling
from app.services.telegram import XATOLIK_CHAT_KALITI, XATOLIK_TOKEN_KALITI


@pytest.fixture()
def bot_sozlangan(db):
    db.add(Sozlama(kalit=XATOLIK_TOKEN_KALITI, qiymat="123:ABC"))
    db.add(Sozlama(kalit=XATOLIK_CHAT_KALITI, qiymat="999"))
    db.commit()


def _callback_yangilanish(update_id: int, callback_data: str, callback_id: str = "cb1") -> dict:
    return {
        "update_id": update_id,
        "callback_query": {
            "id": callback_id,
            "from": {"id": 555, "first_name": "Admin"},
            "data": callback_data,
            "message": {
                "message_id": 42,
                "chat": {"id": 999},
                "text": "Asl xabar matni",
            },
        },
    }


def _partiya_yarat(db, mahsulot_id: int, raqami: int) -> Partiya:
    partiya = Partiya(mahsulot_id=mahsulot_id, partiya_raqami=raqami, holati=PartiyaHolati.ochiq)
    db.add(partiya)
    db.commit()
    db.refresh(partiya)
    return partiya


def _kamera_sorovi_yarat(db, operator, partiya, ogirlik=140.0) -> KameraTasdiqSorovi:
    sorov = KameraTasdiqSorovi(
        mijoz_id=str(uuid.uuid4()),
        partiya_id=partiya.id,
        ogirlik=ogirlik,
        smena=operator.smena,
        operator_id=operator.id,
        mahalliy_vaqt=datetime.now(timezone.utc),
    )
    db.add(sorov)
    db.commit()
    db.refresh(sorov)
    return sorov


def _kip_yarat(db, operator, partiya) -> Kip:
    vaqt = datetime(2026, 9, 10, 9, 0, tzinfo=timezone.utc)
    kip = Kip(
        mijoz_id=str(uuid.uuid4()),
        partiya_id=partiya.id,
        kip_raqami=1,
        ogirlik=150.0,
        smena=operator.smena,
        operator_id=operator.id,
        mahalliy_vaqt=vaqt,
        vaqt=vaqt,
    )
    db.add(kip)
    db.commit()
    db.refresh(kip)
    return kip


def _zayavka_yarat(db, kip, operator, eski_partiya, yangi_mahsulot, yangi_partiya) -> KipTogrilashZayavkasi:
    zayavka = KipTogrilashZayavkasi(
        kip_id=kip.id,
        operator_id=operator.id,
        eski_mahsulot_id=eski_partiya.mahsulot_id,
        eski_partiya_id=eski_partiya.id,
        yangi_mahsulot_id=yangi_mahsulot.id,
        yangi_partiya_id=yangi_partiya.id,
        sabab="Noto'g'ri mahsulot tanlandi",
    )
    db.add(zayavka)
    db.commit()
    db.refresh(zayavka)
    return zayavka


# --- bitta_tsikl ---


def test_bitta_tsikl_token_yoq_bolsa_bosh_royxat(db):
    assert telegram_polling.bitta_tsikl(db) == []


def test_bitta_tsikl_yangilanishlarni_qaytaradi_va_offsetni_saqlaydi(db, monkeypatch, bot_sozlangan):
    yangilanishlar = [_callback_yangilanish(100, "kamera:1:tasdiqlash"), _callback_yangilanish(101, "kamera:1:tasdiqlash")]
    so_ralgan = {}

    def soxta_get(url, **kw):
        so_ralgan["url"] = url
        so_ralgan["params"] = kw.get("params")
        return httpx.Response(200, json={"ok": True, "result": yangilanishlar}, request=httpx.Request("GET", url))

    monkeypatch.setattr(telegram_polling.httpx, "get", soxta_get)

    natija = telegram_polling.bitta_tsikl(db)

    assert natija == yangilanishlar
    assert so_ralgan["url"].endswith("/bot123:ABC/getUpdates")
    assert so_ralgan["params"]["offset"] == 0

    saqlangan_offset = db.get(Sozlama, telegram_polling.OFFSET_SOZLAMA_KALITI)
    assert saqlangan_offset.qiymat == "102"  # eng katta update_id (101) + 1


def test_bitta_tsikl_keyingi_chaqiruv_yangi_offsetdan_boshlaydi(db, monkeypatch, bot_sozlangan):
    db.add(Sozlama(kalit=telegram_polling.OFFSET_SOZLAMA_KALITI, qiymat="55"))
    db.commit()

    so_ralgan = {}

    def soxta_get(url, **kw):
        so_ralgan["params"] = kw.get("params")
        return httpx.Response(200, json={"ok": True, "result": []}, request=httpx.Request("GET", url))

    monkeypatch.setattr(telegram_polling.httpx, "get", soxta_get)
    telegram_polling.bitta_tsikl(db)
    assert so_ralgan["params"]["offset"] == 55


def test_bitta_tsikl_http_xato_bosh_royxat_qaytaradi(db, monkeypatch, bot_sozlangan):
    monkeypatch.setattr(
        telegram_polling.httpx, "get", lambda *a, **k: (_ for _ in ()).throw(httpx.ConnectError("tarmoq yo'q"))
    )
    assert telegram_polling.bitta_tsikl(db) == []


# --- yangilanishni_qayta_ishla: kamera-tasdiq ---


def test_kamera_tasdiqlash_callback_ishlaydi(db, monkeypatch, bot_sozlangan, operator, mahsulot_tola):
    partiya = _partiya_yarat(db, mahsulot_tola.id, 601)
    sorov = _kamera_sorovi_yarat(db, operator, partiya)

    chaqiruvlar = []

    def soxta_post(url, **kw):
        chaqiruvlar.append((url, kw.get("json")))
        return httpx.Response(200, json={"ok": True}, request=httpx.Request("POST", url))

    monkeypatch.setattr(telegram_polling.httpx, "post", soxta_post)

    yangilanish = _callback_yangilanish(1, f"kamera:{sorov.id}:tasdiqlash")
    telegram_polling.yangilanishni_qayta_ishla(db, yangilanish)

    db.refresh(sorov)
    assert sorov.holati == KameraTasdiqHolati.tasdiqlangan
    assert sorov.hal_qilish_manbasi == "telegram"
    assert sorov.hal_qilgan_id is None
    assert sorov.kip_id is not None
    kip = db.get(Kip, sorov.kip_id)
    assert kip.surat_yoli is None

    answer_chaqiruvi = next(c for c in chaqiruvlar if c[0].endswith("/answerCallbackQuery"))
    assert answer_chaqiruvi[1]["callback_query_id"] == "cb1"
    assert "Tasdiqlandi" in answer_chaqiruvi[1]["text"]

    edit_chaqiruvi = next(c for c in chaqiruvlar if c[0].endswith("/editMessageText"))
    assert edit_chaqiruvi[1]["chat_id"] == 999
    assert edit_chaqiruvi[1]["message_id"] == 42
    assert "Tasdiqlandi" in edit_chaqiruvi[1]["text"]
    # Tugmalar olib tashlanishi kerak — aks holda hal qilingan so'rovni
    # qayta-qayta bosish mumkin bo'lib qolardi (reply_markup berilmasa,
    # Telegram eski tugmalarni saqlab qoladi).
    assert edit_chaqiruvi[1]["reply_markup"] == {"inline_keyboard": []}


def test_kamera_rad_etish_callback_kip_yaratmaydi(db, monkeypatch, bot_sozlangan, operator, mahsulot_tola):
    partiya = _partiya_yarat(db, mahsulot_tola.id, 602)
    sorov = _kamera_sorovi_yarat(db, operator, partiya)
    monkeypatch.setattr(
        telegram_polling.httpx,
        "post",
        lambda url, **kw: httpx.Response(200, json={"ok": True}, request=httpx.Request("POST", url)),
    )

    yangilanish = _callback_yangilanish(1, f"kamera:{sorov.id}:rad_etish")
    telegram_polling.yangilanishni_qayta_ishla(db, yangilanish)

    db.refresh(sorov)
    assert sorov.holati == KameraTasdiqHolati.rad_etilgan
    assert sorov.kip_id is None


# --- yangilanishni_qayta_ishla: kip to'g'rilash zayavkasi ---


def test_zayavka_tasdiqlash_callback_kipni_yangilaydi(db, monkeypatch, bot_sozlangan, operator, mahsulot_tola, admin):
    from app.models.mahsulot import Mahsulot as MahsulotModel

    lint = MahsulotModel(kod="lint_tp", nomi="Lint")
    db.add(lint)
    db.commit()
    db.refresh(lint)

    eski_partiya = _partiya_yarat(db, mahsulot_tola.id, 603)
    yangi_partiya = _partiya_yarat(db, lint.id, 604)
    kip = _kip_yarat(db, operator, eski_partiya)
    zayavka = _zayavka_yarat(db, kip, operator, eski_partiya, lint, yangi_partiya)

    monkeypatch.setattr(
        telegram_polling.httpx,
        "post",
        lambda url, **kw: httpx.Response(200, json={"ok": True}, request=httpx.Request("POST", url)),
    )

    yangilanish = _callback_yangilanish(1, f"zayavka:{zayavka.id}:tasdiqlash")
    telegram_polling.yangilanishni_qayta_ishla(db, yangilanish)

    db.refresh(zayavka)
    db.refresh(kip)
    assert zayavka.holati == KipTogrilashHolati.tasdiqlangan
    assert zayavka.hal_qilish_manbasi == "telegram"
    # Telegram orqali hal qilinganda ichki admin identifikatori yo'q — audit
    # yozuvi zaxira (birinchi faol admin) hisobiga yoziladi (kip_togrilash.py
    # _audit_uchun_foydalanuvchi_id()).
    assert kip.partiya_id == yangi_partiya.id
    assert kip.holati.value == "tahrirlangan"


def test_zayavka_rad_etish_callback_kipni_ozgartirmaydi(db, monkeypatch, bot_sozlangan, operator, mahsulot_tola):
    from app.models.mahsulot import Mahsulot as MahsulotModel

    lint = MahsulotModel(kod="lint_tr", nomi="Lint")
    db.add(lint)
    db.commit()
    db.refresh(lint)

    eski_partiya = _partiya_yarat(db, mahsulot_tola.id, 605)
    yangi_partiya = _partiya_yarat(db, lint.id, 606)
    kip = _kip_yarat(db, operator, eski_partiya)
    zayavka = _zayavka_yarat(db, kip, operator, eski_partiya, lint, yangi_partiya)

    monkeypatch.setattr(
        telegram_polling.httpx,
        "post",
        lambda url, **kw: httpx.Response(200, json={"ok": True}, request=httpx.Request("POST", url)),
    )

    yangilanish = _callback_yangilanish(1, f"zayavka:{zayavka.id}:rad_etish")
    telegram_polling.yangilanishni_qayta_ishla(db, yangilanish)

    db.refresh(zayavka)
    db.refresh(kip)
    assert zayavka.holati == KipTogrilashHolati.rad_etilgan
    assert kip.partiya_id == eski_partiya.id


# --- Chetga chiqish holatlari ---


def test_callback_query_yoq_yangilanish_etiborsiz_qoldiriladi(db, monkeypatch, bot_sozlangan):
    monkeypatch.setattr(
        telegram_polling.httpx, "post", lambda *a, **k: (_ for _ in ()).throw(AssertionError("chaqirilmasligi kerak"))
    )
    telegram_polling.yangilanishni_qayta_ishla(db, {"update_id": 1, "message": {"text": "salom"}})


def test_notogri_callback_data_formati_ogohlantirish_beradi(db, monkeypatch, bot_sozlangan):
    chaqiruvlar = []
    monkeypatch.setattr(
        telegram_polling.httpx,
        "post",
        lambda url, **kw: chaqiruvlar.append(kw.get("json")) or httpx.Response(200, json={"ok": True}, request=httpx.Request("POST", url)),
    )
    telegram_polling.yangilanishni_qayta_ishla(db, _callback_yangilanish(1, "notogri-format"))
    assert len(chaqiruvlar) == 1
    assert chaqiruvlar[0]["show_alert"] is True


def test_topilmagan_sorov_id_ogohlantirish_beradi(db, monkeypatch, bot_sozlangan):
    chaqiruvlar = []
    monkeypatch.setattr(
        telegram_polling.httpx,
        "post",
        lambda url, **kw: chaqiruvlar.append(kw.get("json")) or httpx.Response(200, json={"ok": True}, request=httpx.Request("POST", url)),
    )
    telegram_polling.yangilanishni_qayta_ishla(db, _callback_yangilanish(1, "kamera:999999:tasdiqlash"))
    assert len(chaqiruvlar) == 1
    assert "topilmadi" in chaqiruvlar[0]["text"].lower()

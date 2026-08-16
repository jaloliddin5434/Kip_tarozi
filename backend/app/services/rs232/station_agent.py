"""Mahalliy stansiya agenti.

Tarozi (RS232) va kamera jismonan operator kompyuteriga ulangani uchun, bu
alohida, yengil FastAPI ilovasi bo'lib, asosiy backend (VPS)dan mustaqil
ishlaydi va operator kompyuterida NSSM orqali Windows xizmati sifatida
o'rnatiladi (mavjud tarozi-tizimidagi pattern bilan bir xil).

Flutter operator ekrani shu agentga (localhost) ulanadi:
  GET  /holat            -> ulanish, og'irlik, anti-o'g'irlik holati, navbat uzunligi
  WS   /oqim              -> real-vaqt oqim (0.3s)
  POST /agent/kontekst    -> Flutter tanlagan mahsulot/smenani agentga bildiradi
  POST /agent/kip         -> kip saqlash (backendga forward, aloqa yo'q bo'lsa offline navbatga)
  POST /agent/tasdiqla    -> operator 'Tushundim' bosdi — blok ochiladi

Kip saqlash Flutter'dan TO'G'RIDAN-TO'G'RI backendga emas, shu agent orqali
o'tadi — shunda offline holatda ham operator ishni davom ettira oladi va
anti-o'g'irlik state machine har bir saqlashdan xabardor bo'ladi.
"""

import asyncio
import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import datetime

import httpx
from fastapi import FastAPI, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse

from app.core.config import settings
from app.services.rs232 import navbat
from app.services.rs232.anti_ogirlik import AntiOgirlikHolati, AntiOgirlikNazorati
from app.services.rs232.bus import OgirlikKanali
from app.services.rs232.camera import snapshot_ol
from app.services.rs232.reader import OgirlikOquvchi
from app.services.rs232.sinxron import SinxronIshchisi
from app.services.rs232.stability import BarqarorlikTekshiruvchisi
from app.services.rs232.watchdog import RS232Watchdog

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("station_agent")

kanal = OgirlikKanali()
oquvchi = OgirlikOquvchi(kanal)
watchdog = RS232Watchdog(oquvchi)
barqarorlik = BarqarorlikTekshiruvchisi(kanal)
sinxron_ishchisi = SinxronIshchisi()


def _hodisani_backendga_yubor(ogirlik: float, vaqt: datetime, smena: str | None, mahsulot_kodi: str | None) -> int | None:
    rasm = snapshot_ol()
    fayllar = {"surat": ("hodisa.jpg", rasm, "image/jpeg")} if rasm else None
    malumot = {"ogirlik": str(ogirlik), "vaqt": vaqt.isoformat()}
    if smena:
        malumot["smena"] = smena
    if mahsulot_kodi:
        malumot["mahsulot_kodi"] = mahsulot_kodi

    javob = httpx.post(
        f"{settings.BACKEND_URL}/api/v1/shubhali-holatlar",
        data=malumot,
        files=fayllar,
        headers={"X-Agent-Key": settings.AGENT_API_KEY},
        timeout=10,
    )
    javob.raise_for_status()
    return javob.json().get("id")


anti_ogirlik = AntiOgirlikNazorati(kanal, _hodisani_backendga_yubor)


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    watchdog.ishga_tushir()
    sinxron_ishchisi.ishga_tushir()
    yield
    sinxron_ishchisi.toxtat()
    watchdog.toxtat()


app = FastAPI(title="Kip Tarozi — Stansiya Agenti", lifespan=lifespan)


@app.get("/holat")
def holat() -> dict:
    return {
        "ulangan": watchdog.holat.ulangan,
        "oxirgi_xato": watchdog.holat.oxirgi_xato,
        "joriy_ogirlik": barqarorlik.joriy_ogirlik,
        "barqarormi": barqarorlik.barqarormi(),
        "anti_ogirlik_holati": anti_ogirlik.holat.value,
        "navbat_uzunligi": navbat.uzunlik(),
    }


@app.websocket("/oqim")
async def oqim(websocket: WebSocket) -> None:
    await websocket.accept()
    try:
        while True:
            await websocket.send_json(
                {
                    "ogirlik": barqarorlik.joriy_ogirlik,
                    "barqarormi": barqarorlik.barqarormi(),
                    "ulangan": watchdog.holat.ulangan,
                    "anti_ogirlik_holati": anti_ogirlik.holat.value,
                    "navbat_uzunligi": navbat.uzunlik(),
                }
            )
            await asyncio.sleep(0.3)
    except WebSocketDisconnect:
        pass


@app.post("/agent/kontekst")
async def kontekst_ornat(req: Request) -> dict:
    """Flutter operator qaysi mahsulot/partiyani tanlaganini shu yerga bildiradi —
    'yuk saqlanmadi' hodisasi shu kontekst bilan (rasm papkasi uchun) yoziladi."""
    payload = await req.json()
    anti_ogirlik.kontekst_ornat(payload.get("mahsulot_kodi"), payload.get("smena"))
    return {"holat": "ok"}


@app.post("/agent/kip")
async def kip_saqlash(req: Request) -> JSONResponse:
    tanish = req.headers.get("authorization")
    if not tanish:
        return JSONResponse({"detail": "Avtorizatsiya headeri kerak"}, status_code=401)

    payload = await req.json()
    mijoz_id = payload.get("mijoz_id")
    if not mijoz_id:
        return JSONResponse({"detail": "mijoz_id majburiy"}, status_code=400)

    if anti_ogirlik.holat == AntiOgirlikHolati.bloklangan:
        return JSONResponse(
            {"detail": "Tasdiqlanmagan 'yuk saqlanmadi' ogohlantirishi bor — avval uni tasdiqlang"},
            status_code=409,
        )

    token = tanish.removeprefix("Bearer ").strip()
    try:
        javob = httpx.post(
            f"{settings.BACKEND_URL}/api/v1/kiplar",
            json=payload,
            headers={"Authorization": tanish},
            timeout=5,
        )
    except (httpx.ConnectError, httpx.TimeoutException):
        navbat.qoshish(mijoz_id, token, payload)
        anti_ogirlik.saqlandi_deb_belgila()
        logger.info("Backendga ulanib bo'lmadi, offline navbatga qo'yildi: %s", mijoz_id)
        return JSONResponse({"holat": "navbatga_qoyildi", "mijoz_id": mijoz_id}, status_code=202)

    if javob.status_code >= 500:
        navbat.qoshish(mijoz_id, token, payload)
        anti_ogirlik.saqlandi_deb_belgila()
        logger.warning("Backend server xatosi (%s), offline navbatga qo'yildi: %s", javob.status_code, mijoz_id)
        return JSONResponse({"holat": "navbatga_qoyildi", "mijoz_id": mijoz_id}, status_code=202)

    if javob.status_code < 400:
        anti_ogirlik.saqlandi_deb_belgila()

    return JSONResponse(javob.json(), status_code=javob.status_code)


@app.post("/agent/tasdiqla")
async def tasdiqla(req: Request) -> JSONResponse:
    tanish = req.headers.get("authorization")
    if not tanish:
        return JSONResponse({"detail": "Avtorizatsiya headeri kerak"}, status_code=401)

    hodisa_id = anti_ogirlik.joriy_hodisa_id
    if hodisa_id is None:
        anti_ogirlik.tasdiqlandi()
        return JSONResponse({"holat": "ok"})

    javob = httpx.patch(
        f"{settings.BACKEND_URL}/api/v1/shubhali-holatlar/{hodisa_id}/tasdiqla",
        headers={"Authorization": tanish},
        timeout=10,
    )
    if javob.status_code >= 400:
        return JSONResponse(javob.json(), status_code=javob.status_code)

    anti_ogirlik.tasdiqlandi()
    return JSONResponse({"holat": "ok"})

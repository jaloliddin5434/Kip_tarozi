from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1.router import api_router
from app.api.v1.routes import media
from app.core.config import settings
from app.services import rejalashtiruvchi, telegram_polling


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    rejalashtiruvchi.ishga_tushir()
    telegram_polling.ishga_tushir()
    yield
    telegram_polling.toxtat()
    rejalashtiruvchi.toxtat()


app = FastAPI(title="Kip Tarozi — Backend", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Flutter web ilova manzili aniqlangach toraytiriladi
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router, prefix="/api/v1")

# STORAGE_PATH mavjudligini ta'minlaymiz (suratlar, nakladnoy PDF va h.k. shu
# yerga yoziladi). AUDIT TUZATISHI: bu papka ilgari `StaticFiles` bilan hech
# qanday autentifikatsiyasiz `/media`ga to'g'ridan-to'g'ri mount qilingan edi —
# endi shu papkadagi fayllar FAQAT `app/api/v1/routes/media.py`dagi
# autentifikatsiyalangan endpointlar orqali (JWT + ruxsat tekshiruvi bilan)
# beriladi.
Path(settings.STORAGE_PATH).mkdir(parents=True, exist_ok=True)
app.include_router(media.router)


@app.get("/salomat")
def salomat() -> dict:
    return {"holat": "ishlayapti"}

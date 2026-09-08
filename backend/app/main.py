from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.api.v1.router import api_router
from app.core.config import settings
from app.services import rejalashtiruvchi


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    rejalashtiruvchi.ishga_tushir()
    yield
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

# Saqlangan suratlar (kip surati, shubhali holat surati) — frontend Image.network
# orqali shu manzildan ochadi. surat_ommaviy_url() shu bilan mos yo'l qaytaradi.
_media_papka = Path(settings.STORAGE_PATH)
_media_papka.mkdir(parents=True, exist_ok=True)
app.mount("/media", StaticFiles(directory=_media_papka), name="media")


@app.get("/salomat")
def salomat() -> dict:
    return {"holat": "ishlayapti"}

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1.router import api_router
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


@app.get("/salomat")
def salomat() -> dict:
    return {"holat": "ishlayapti"}

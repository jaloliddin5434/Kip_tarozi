from fastapi import APIRouter

from app.api.v1.routes import (
    agent,
    auth,
    dashboard,
    hujjatlar,
    kiplar,
    mahsulotlar,
    moliyaviy,
    partiyalar,
    shubhali_holatlar,
    sozlamalar,
    statistika,
)

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(mahsulotlar.router)
api_router.include_router(partiyalar.router)
api_router.include_router(kiplar.router)
api_router.include_router(shubhali_holatlar.router)
api_router.include_router(hujjatlar.router)
api_router.include_router(statistika.router)
api_router.include_router(dashboard.router)
api_router.include_router(sozlamalar.router)
api_router.include_router(agent.router)
api_router.include_router(moliyaviy.router)

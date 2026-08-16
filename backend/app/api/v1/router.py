from fastapi import APIRouter

from app.api.v1.routes import auth, kiplar, mahsulotlar, partiyalar, shubhali_holatlar

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(mahsulotlar.router)
api_router.include_router(partiyalar.router)
api_router.include_router(kiplar.router)
api_router.include_router(shubhali_holatlar.router)

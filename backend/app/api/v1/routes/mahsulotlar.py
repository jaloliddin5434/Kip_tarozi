from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import joriy_foydalanuvchi
from app.core.database import get_db
from app.models.mahsulot import Mahsulot
from app.schemas.mahsulot import MahsulotJavob

router = APIRouter(prefix="/mahsulotlar", tags=["mahsulotlar"])


@router.get("", response_model=list[MahsulotJavob])
def royxat(db: Session = Depends(get_db), _=Depends(joriy_foydalanuvchi)) -> list[Mahsulot]:
    return list(db.scalars(select(Mahsulot).where(Mahsulot.faol.is_(True)).order_by(Mahsulot.id)))

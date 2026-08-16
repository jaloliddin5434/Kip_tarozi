from datetime import datetime

from pydantic import BaseModel, ConfigDict


class SozlamaYangilash(BaseModel):
    qiymat: str
    tavsif: str | None = None


class SozlamaJavob(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    kalit: str
    qiymat: str
    tavsif: str | None
    yangilangan_vaqt: datetime

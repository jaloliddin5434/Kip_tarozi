from pydantic import BaseModel, ConfigDict


class MahsulotJavob(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    kod: str
    nomi: str

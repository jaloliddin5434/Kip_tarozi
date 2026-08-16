from typing import Generic, TypeVar

from pydantic import BaseModel

T = TypeVar("T")


class Sahifalangan(BaseModel, Generic[T]):
    items: list[T]
    jami: int
    sahifa: int
    sahifa_hajmi: int

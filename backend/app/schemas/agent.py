from pydantic import BaseModel


class AgentHolatYangilash(BaseModel):
    ulangan: bool
    oxirgi_xato: str | None = None
    anti_ogirlik_holati: str
    navbat_uzunligi: int

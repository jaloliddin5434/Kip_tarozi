import json
from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.deps import agent_autentifikatsiya
from app.core.database import get_db
from app.models.sozlama import Sozlama
from app.schemas.agent import AgentHolatYangilash

router = APIRouter(prefix="/agent-holat", tags=["agent"])

AGENT_HOLAT_KALITI = "agent_oxirgi_holat"


@router.post("")
def holat_yuborish(
    malumot: AgentHolatYangilash,
    db: Session = Depends(get_db),
    _: None = Depends(agent_autentifikatsiya),
) -> dict:
    """Stansiya Agenti AGENT_HOLAT_YUBORISH_SONIYA oralig'ida shu yerga
    'salomatman' xabarini yuboradi — Dashboard shu ma'lumotni ko'rsatadi
    (VPS operator PC ichki tarmog'iga to'g'ridan-to'g'ri kira olmaydi,
    shuning uchun push-model ishlatiladi)."""
    qiymat = {
        "ulangan": malumot.ulangan,
        "oxirgi_xato": malumot.oxirgi_xato,
        "anti_ogirlik_holati": malumot.anti_ogirlik_holati,
        "navbat_uzunligi": malumot.navbat_uzunligi,
        "vaqt": datetime.now(timezone.utc).isoformat(),
    }

    sozlama = db.get(Sozlama, AGENT_HOLAT_KALITI)
    if sozlama is None:
        sozlama = Sozlama(kalit=AGENT_HOLAT_KALITI, qiymat=json.dumps(qiymat), tavsif="Stansiya agentining oxirgi holati")
        db.add(sozlama)
    else:
        sozlama.qiymat = json.dumps(qiymat)
    db.commit()

    return {"holat": "ok"}

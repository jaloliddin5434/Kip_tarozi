from app.core.database import SessionLocal
from app.core.security import parolni_hash
from app.models.foydalanuvchi import Foydalanuvchi

db = SessionLocal()
u = db.query(Foydalanuvchi).filter_by(login='operator_a').first()
u.parol_hash = parolni_hash('SIZNING_YANGI_PAROLINGIZ')
db.commit()
print('parol yangilandi')
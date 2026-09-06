from app.core.database import SessionLocal
from app.core.security import parolni_hash
from app.models.foydalanuvchi import Foydalanuvchi

db = SessionLocal()
u = db.query(Foydalanuvchi).filter_by(login='admin').first()
u.parol_hash = parolni_hash('Admin_2026x')
db.commit()
print('admin paroli yangilandi')
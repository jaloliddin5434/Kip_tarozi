# Kip Tarozi

Paxta zavodida kip (Tola/Lint/Pux/Ulyuk)ni tortish, hisobga olish, partiyalarga
guruhlash va sotishgacha kuzatib borish tizimi.

## Arxitektura

Tizim ikkita mustaqil deployable qismdan iborat (batafsil: [docs/ARXITEKTURA.md](docs/ARXITEKTURA.md)):

- **`backend/`** — FastAPI + PostgreSQL, VPS'da ishlaydi. Auth/RBAC, partiya/kip
  biznes-mantig'i, admin panel API, hujjat generatsiyasi.
- **`backend/app/services/rs232`** (Stansiya Agenti) — operator kompyuterida
  (tarozi/kamera ulangan joyda) NSSM orqali Windows xizmati sifatida ishlaydi.
  RS232'ni o'qiydi, barqarorlikni tekshiradi, watchdog bilan qayta ulanadi.
- **`frontend/`** — Flutter ilova (operator ekrani + admin panel + mobil
  ko'rish). Keyingi bosqichlarda qo'shiladi.

## Backend'ni ishga tushirish (dev)

```powershell
cd backend
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
copy .env.example .env
# .env ichida DATABASE_URL va SECRET_KEY ni to'ldiring

alembic revision --autogenerate -m "boshlangich sxema"
alembic upgrade head
python -m scripts.seed   # birinchi admin, 4 mahsulot, standart stansiya

uvicorn app.main:app --reload --port 8000
```

## Stansiya agentini ishga tushirish (operator kompyuterida, dev)

```powershell
cd backend
.venv\Scripts\activate
uvicorn app.services.rs232.station_agent:app --port 8100
```

Ishlab chiqarishda ikkalasi ham NSSM orqali Windows xizmati sifatida
o'rnatiladi (mavjud tarozi-tizimidagi pattern bilan bir xil).

## Loyiha bosqichlari

1. **✅** Baza sxemasi + backend skeleton + auth/RBAC + RS232 agent
2. **✅** Operator jarayoni (tortish, partiya/kip logikasi) + anti-o'g'irlik nazorati + offline queue
3. **✅ (joriy)** Admin panel — Hujjatlar, Statistika, Partiyalar, Dashboard, Sozlamalar, Telegram
4. Moliyaviy bo'lim, mobil ilova, to'liq sinov va VPS'ga joylashtirish

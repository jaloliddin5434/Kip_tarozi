# Kip Tarozi

Paxta zavodida kip (Tola/Lint/Pux/Ulyuk)ni tortish, hisobga olish, partiyalarga
guruhlash va sotishgacha kuzatib borish tizimi.

## Arxitektura

Tizim uchta mustaqil deployable qismdan iborat (batafsil: [docs/ARXITEKTURA.md](docs/ARXITEKTURA.md)):

- **`backend/`** — FastAPI + PostgreSQL, VPS'da ishlaydi. Auth/RBAC, partiya/kip
  biznes-mantig'i, admin panel API, moliyaviy bo'lim, Telegram integratsiyasi.
- **`backend/app/services/rs232`** (Stansiya Agenti) — operator kompyuterida
  (tarozi/kamera ulangan joyda) NSSM orqali Windows xizmati sifatida ishlaydi.
  RS232'ni o'qiydi, barqarorlikni va anti-o'g'irlikni kuzatadi, offline
  navbatni boshqaradi, watchdog bilan qayta ulanadi.
- **`frontend/`** — Flutter ilova (operator ekrani + admin panel), web va
  Windows/macOS desktop uchun.

## Backend'ni ishga tushirish (dev)

```powershell
cd backend
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements-dev.txt   # yoki requirements.txt (test kutubxonalarisiz)
copy .env.example .env
# .env ichida DATABASE_URL va SECRET_KEY ni to'ldiring

alembic upgrade head
python -m scripts.seed   # birinchi admin, 4 mahsulot, standart stansiya

uvicorn app.main:app --reload --port 8000
```

Backend ishga tushgach: `http://localhost:8000/docs` — Swagger orqali barcha
endpointlarni sinab ko'rish mumkin.

### Testlar

```powershell
cd backend
pytest
```

Ko'p testlar (auth, partiya/kip oqimi, moliyaviy) haqiqiy PostgreSQL'ga
muhtoj — `DATABASE_URL`dagi nom + `_test` bo'lgan bazani avtomatik qidiradi
(masalan `kip_tarozi` bo'lsa `kip_tarozi_test`). Agar shu baza topilmasa,
DB'ga bog'liq testlar avtomatik `skip` qilinadi, faqat sof-mantiq testlari
(davr hisoblash, anti-o'g'irlik state machine, offline navbat) ishlaydi.
Boshqa manzil kerak bo'lsa `TEST_DATABASE_URL` environment o'zgaruvchisini
sozlang.

## Stansiya agentini ishga tushirish (operator kompyuterida, dev)

```powershell
cd backend
.venv\Scripts\activate
uvicorn app.services.rs232.station_agent:app --port 8100
```

Ishlab chiqarishda ikkalasi ham NSSM orqali Windows xizmati sifatida
o'rnatiladi (mavjud tarozi-tizimidagi pattern bilan bir xil). Joylashtirish
qadamlari: [docs/VPS_JOYLASHTIRISH.md](docs/VPS_JOYLASHTIRISH.md).

## Frontend'ni ishga tushirish (dev)

```powershell
cd frontend
flutter pub get
flutter run -d chrome
```

Backend manzili `lib/api/api_client.dart`dagi `ApiClient.bazaUrl`da
sozlanadi (default: `http://localhost:8000/api/v1`). VPS/domen aniqlangach
shu qiymat (yoki build-time `--dart-define`) o'zgartiriladi.

**Muhim izoh (joriy holat):** operator ekranidagi og'irlik maydoni hozircha
RS232 real qurilma bo'lmagani uchun QO'LDA kiritiladigan simulyatsiya —
Stansiya Agentining real-vaqt WebSocket oqimi (`/oqim`) va anti-o'g'irlik
kontekst integratsiyasi RS232 indikatori aniqlangach ulanadi. Kip saqlash
hozircha backendga to'g'ridan-to'g'ri (REST) boradi; offline-navbat orqali
agentga proksi qilish — real qurilma bilan sinovdan keyingi qadam.

### Testlar

```powershell
cd frontend
flutter analyze
flutter test                    # sof widget testi, backend shart emas
```

`test/operator_oqimi_test.dart`, `test/admin_oqimi_test.dart` va
`test/yuk_saqlanmadi_test.dart` — HAQIQIY backendga ulanadigan integratsion
testlar (login → partiya ochish → kip saqlash → anti-o'g'irlik modali
to'liq oqimini haqiqiy Postgres orqali tekshiradi). Ishga tushirish uchun
backend ishlab turishi kerak:

```powershell
flutter test --dart-define=BACKEND_URL=http://localhost:8000/api/v1
```

## Loyiha bosqichlari

1. **✅** Baza sxemasi + backend skeleton + auth/RBAC + RS232 agent
2. **✅** Operator jarayoni (tortish, partiya/kip logikasi) + anti-o'g'irlik nazorati + offline queue
3. **✅** Admin panel — Hujjatlar, Statistika, Partiyalar, Dashboard, Sozlamalar, Telegram
4. **✅** Moliyaviy bo'lim + Flutter frontend (operator/admin ekranlari) + testlar + VPS checklist
5. **✅ (joriy)** Mustaqil audit + tezkor tuzatishlar — i18n (Sotish formasi + jadval sarlavhalari),
   Hujjatlar bo'limida chop etish tugmasi (PDF), Shubhali holatlar admin bo'limi
   (ro'yxat + filtr), `stansiya_id`ning haqiqiy uchdan-uchgacha ulanishi

### Ma'lum cheglovlar (aniq so'ralganda qilinadi)

Bular — 4-bosqichdan keyin o'tkazilgan mustaqil auditda aniqlangan, hali
qilinmagan yoki faqat stub holatidagi qismlar:

- Real RS232 indikator bilan ulanish (model aniqlangach) — watchdog kodi
  yozilgan, lekin real yoki hatto soxta port uzilishi bilan sinalmagan
- Real IP kamera bilan surat olish — kod yozilgan, hech qachon chaqirilmagan
- "Admin ruxsati bilan kamerasiz davom etish" — umuman qurilmagan
- Offline-navbat to'liq zanjiri (agent → SQLite → avtomatik sinxron) — faqat
  SQLite mexanikasi sinaldi, backend bilan to'liq oqim hech qachon jonli
  ishga tushirilmagan
- Nakladnoy PDF generatsiyasi (hozircha stub — faqat raqam yaratiladi)
- Excel/smena-mavsum jurnal avtomatizatsiyasi — umuman yozilmagan
- Real Telegram bot tokenlari bilan ulash — kod yozilgan, hech qachon real
  token bilan sinalmagan
- UZEX real integratsiyasi (hozircha stub — soxta narxlar)
- Kunlik avtomatik backup skripti va test-ma'lumotlarni tozalash skripti
- Ko'p-stansiyali sozlash haqiqiy 2-stansiyada hech qachon sinalmagan
  (bitta stansiyada `stansiya_id` oqimi tasdiqlangan, xolos)
- VPS'ga haqiqiy joylashtirish ([checklist](docs/VPS_JOYLASHTIRISH.md) tayyor)
- Mobil (Android/iOS) faqat-ko'rish ilovasi — platforma hatto scaffold
  qilinmagan
- Admin panelda Sozlamalar va Moliyaviy bo'lim uchun Flutter ekranlari
  (backend API tayyor, UI yo'q)

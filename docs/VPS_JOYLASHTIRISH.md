# VPS'ga joylashtirish checklist

Bu hujjat — haqiqiy joylashtirish content emas, faqat tayyorgarlik ro'yxati.
Aniq VPS ma'lumotlari (IP, OS, kirish) berilgach amalga oshiriladi.

## 0. Oldindan hal qilinishi kerak bo'lgan savollar

- [ ] VPS operatsion tizimi — Windows Server (NSSM pattern shu holatda ishlaydi
      o'zgarishsiz) yoki Linux (bo'lsa, NSSM o'rniga systemd unit fayllariga
      almashtirish kerak bo'ladi)?
- [ ] Domen bormi yoki hozircha faqat IP orqali ishlaydimi?
- [ ] Operator kompyuteri(lari) VPS bilan bir xil LAN'dami yoki internet orqali
      ulanadimi (Stansiya Agenti → Backend `BACKEND_URL` shunga qarab sozlanadi)?

## 1. Server tayyorlash

- [ ] Python 3.11+ o'rnatilgan
- [ ] PostgreSQL 14+ o'rnatilgan va ishga tushirilgan
- [ ] `kip_tarozi` bazasi va alohida foydalanuvchi (kuchli parol bilan) yaratilgan
- [ ] Firewall: faqat kerakli portlar ochiq (backend — masalan 8000, Postgres
      — faqat localhost/LAN, RDP/SSH — cheklangan IP'lardan)
- [ ] NSSM yuklab olingan (agar Windows Server bo'lsa)

## 2. Backend joylashtirish

- [ ] Repo VPS'ga klonlangan (`git clone`)
- [ ] `backend/.venv` yaratilgan, `pip install -r requirements.txt`
- [ ] `backend/.env` prod qiymatlar bilan to'ldirilgan:
  - [ ] `DATABASE_URL` — prod baza
  - [ ] `SECRET_KEY` — `openssl rand -hex 32` bilan yangi generatsiya (repo'dagi
        namuna bilan BIR XIL BO'LMASIN)
  - [ ] `AGENT_API_KEY` — yangi tasodifiy qiymat, operator kompyuterlaridagi
        stansiya agent `.env`lariga ham shu bir xil qiymat yoziladi
  - [ ] `STORAGE_PATH` — yetarli diskli alohida joy (suratlar/hujjatlar uchun)
  - [ ] `BACKEND_URL` — bu backendning o'zi uchun emas, operator kompyuteridagi
        agent `.env`ida backendga qanday murojaat qilishini bildiradi
- [ ] `alembic upgrade head` — bazani so'nggi holatga keltirish
- [ ] `python -m scripts.seed` — birinchi admin, 4 mahsulot, standart stansiya
- [ ] NSSM orqali Windows xizmati sifatida o'rnatish:
      `nssm install KipTaroziBackend "...\.venv\Scripts\python.exe" "-m uvicorn app.main:app --host 0.0.0.0 --port 8000"`
      — **`--workers` BERILMASIN (yoki aniq `--workers 1`)**, pastdagi
      eslatmaga qarang.
- [ ] Xizmat avtomatik qayta ishga tushishi sozlangan (`nssm set ... AppExit Default Restart`)
- [ ] `GET /salomat` orqali ishga tushgani tekshirilgan

> **TAVSIYA: `--workers 1`.** Backend ishga tushganda (`app/main.py`
> `lifespan()`) ikkita fon jarayonni boshlaydi — Telegram getUpdates
> long-polling (`telegram_polling.py`) va kunlik hisobot rejalashtiruvchisi
> (`rejalashtiruvchi.py`). Ikkalasi ham PostgreSQL advisory lock
> (`pg_try_advisory_lock`, `app/services/advisory_lock.py`) orqali **kod
> darajasida** himoyalangan — agar kelajakda ko'p worker (`uvicorn
> --workers N`) yoki bir nechta backend nusxasi ishga tushirilsa, faqat
> BITTASI haqiqatan pollashni/rejalashtirishni boshlaydi, qolganlari
> `backup.log`/dastur logida "advisory lock band — bu workerda ishga
> tushirilmaydi" deb yozib, hech narsa qilmaydi (Telegram 409 Conflict va
> kunlik hisobotning N marta takrorlanishining oldi olingan). Shunga
> qaramay, **bitta worker bilan ishga tushirish tavsiya etiladi** — bu
> oddiyroq, resurs isrof qilmaydi (ortiqcha workerlarning har biri baribir
> advisory lock uchun bitta DB ulanishni butun ishga tushgan davri
> davomida band qilib turadi) va debug qilishni osonlashtiradi.

## 3. Stansiya Agenti (har bir operator kompyuterida)

- [ ] Repo (yoki faqat `backend/` qismi) operator kompyuteriga ko'chirilgan
- [ ] `.venv` + `pip install -r requirements.txt`
- [ ] `.env`da: `RS232_PORT`/`RS232_BAUDRATE`/`RS232_REGEX` — haqiqiy indikator
      bo'yicha sozlangan, `BACKEND_URL` — VPS manzili, `AGENT_API_KEY` — backend
      bilan BIR XIL
- [ ] `CAMERA_SNAPSHOT_URL` — IP kamera HTTP snapshot manzili sozlangan
- [ ] NSSM orqali xizmat: `uvicorn app.services.rs232.station_agent:app --port 8100`
- [ ] RS232 portga ulanish sinovdan o'tkazilgan (`GET /holat`)

## 4. Flutter frontend

- [ ] `flutter build web` — production build
- [ ] `lib/api/api_client.dart`dagi `bazaUrl` (yoki build-time
      `--dart-define=BACKEND_URL=...`) VPS manziliga sozlangan
- [ ] Build natijasi (`build/web`) biror statik server orqali (nginx, IIS,
      yoki backend'ning o'zidan `StaticFiles` bilan) ulashtirilgan
- [ ] Windows/macOS desktop kerak bo'lsa: `flutter build windows` /
      `flutter build macos` — alohida operator kompyuterlarida ishlatish uchun

## 5. Backup

- [ ] Kunlik avtomatik PostgreSQL backup skripti (`pg_dump`) — VPS + tashqi
      joy (masalan boshqa server yoki bulut xotira). Skript va sozlash
      yo'riqnomasi: [BACKUP.md](BACKUP.md)
- [ ] Backup'ni tiklab sinash (restore test) — kamida bir marta qo'lda
      bajarilib, ma'lumotlar to'g'ri tiklanganligi tasdiqlangan
- [ ] `STORAGE_PATH` (suratlar/hujjatlar) ham backup rejasiga kiritilgan

## 6. Xavfsizlik

- [ ] `SECRET_KEY`, `AGENT_API_KEY` — namunaviy qiymatlar emas, real generatsiya
      qilingan
- [ ] Moliyaviy bo'lim paroli o'rnatilgan (`POST /moliyaviy/parolni-ornatish`)
- [ ] Postgres — faqat kerakli IP/localhostdan ulanishga ruxsat
- [ ] CORS (`app/main.py`dagi `allow_origins=["*"]`) — Flutter web manzili
      aniqlangach real domenga toraytiriladi

## 7. Ishga tushirishdan keyin

- [ ] Telegram: `sozlamalar` jadvaliga real bot token/chat_id kiritilgan
      (`PUT /sozlamalar/telegram_xatolik_bot_token` va h.k.)
- [ ] Test bosqichida yozilgan sinov ma'lumotlari tozalangan (haqiqiy mavsum
      boshlanishidan oldin bazani nolga qaytarish — alohida skript kerak
      bo'lsa so'rang)
- [ ] Barcha rollar (Admin, Operator smenalari, Tayyor mahsulotlar) uchun
      haqiqiy login/parollar yaratilgan, namuna parollar o'chirilgan

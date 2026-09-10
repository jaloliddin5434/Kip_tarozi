# NSSM orqali Windows xizmatlarini o'rnatish

Backend (uvicorn) va Stansiya Agentni Windows xizmati sifatida o'rnatish
uchun skriptlar:

- [scripts/nssm_ornatish.ps1](../scripts/nssm_ornatish.ps1) — o'rnatadi
- [scripts/nssm_ochirish.ps1](../scripts/nssm_ochirish.ps1) — o'chiradi

## Xizmat nomlari haqida — MUHIM

Bu skriptlar quyidagi ikkita xizmatni yaratadi:

- **KipTaroziBackend** — FastAPI backend (`app.main:app`)
- **KipTaroziAgent** — Stansiya agenti (`app.services.rs232.station_agent:app`)

Bu nomlar loyihadagi **boshqa** mavjud xizmatlardan (masalan
`HazoraspBackend`, `HazoraspFrontend`, `CloudflaredTunnel`) ataylab
farqlanadi. Ikkala skript ham ishga tushishdan oldin xizmat nomlarini shu
taqiqlangan ro'yxat bilan solishtiradi va to'qnashuv bo'lsa darhol
to'xtaydi — bu himoya kod ichida qattiq yozilgan (hardcode), parametr
orqali chetlab o'tib bo'lmaydi. `nssm_ochirish.ps1` esa umuman boshqa
xizmat nomini bilmaydi — faqat shu ikkitasiga tegadi.

## 1. NSSM'ni o'rnatish (oldindan bir marta qilinadi)

NSSM (Non-Sucking Service Manager) kompyuterda alohida o'rnatilgan
bo'lishi kerak — bu skriptlar uni o'zi yuklab olmaydi.

1. https://nssm.cc/download saytidan so'nggi versiyani yuklab oling
   (`nssm-2.24.zip` yoki undan keyingisi).
2. Arxivni oching, kompyuter arxitekturasiga mos papkani tanlang
   (odatda `win64`).
3. `nssm.exe`ni doimiy joyga ko'chiring, masalan `C:\nssm\nssm.exe`.
4. Shu papkani tizim `PATH`iga qo'shing (Administrator sifatida):
   ```
   setx PATH "$env:PATH;C:\nssm" /M
   ```
   yoki Boshqaruv paneli → Tizim → Qo'shimcha tizim sozlamalari →
   Environment Variables orqali qo'lda qo'shing. **PowerShell'ni qayta
   ishga tushiring** — PATH o'zgarishi joriy sessiyada ko'rinmaydi.
5. Tekshirish: `nssm.exe` yozganda buyruq topilishi kerak:
   ```
   Get-Command nssm.exe
   ```

PATH'ga qo'shishni istamasangiz, skriptlarga `-NssmPath` parametri orqali
to'liq yo'lni ko'rsatishingiz ham mumkin (pastga qarang).

## 2. O'rnatish

Administrator huquqidagi PowerShell'da:

```
powershell -ExecutionPolicy Bypass -File scripts\nssm_ornatish.ps1
```

Standart holatda skript loyihani `C:\Kip_tarozi`da deb hisoblaydi va
`backend\.venv\Scripts\python.exe`ni ishlatadi. Boshqacha bo'lsa:

```
powershell -ExecutionPolicy Bypass -File scripts\nssm_ornatish.ps1 `
    -ProjectRoot "D:\Kip_tarozi" `
    -NssmPath "C:\nssm\nssm.exe" `
    -BackendPort 8000 `
    -AgentPort 8100
```

Skript xizmatlarni o'rnatadi, lekin **ishga tushirmaydi** (o'zingiz
tekshirib, keyin ishga tushirishingiz uchun) — agar darhol ishga tushirish
kerak bo'lsa, `-XizmatlarniIshgaTushirish` qo'shing.

Har bir xizmat uchun avtomatik sozlanadigan narsalar:

- **Watchdog**: xizmat qanday sababdan to'xtamasin (xatolik, qulash),
  NSSM uni 3 soniyadan keyin avtomatik qayta ishga tushiradi
  (`AppExit Default Restart`).
- **Avtomatik start**: kompyuter qayta yoqilganda xizmat o'zi ishga
  tushadi (`Start SERVICE_AUTO_START`).
- **Log fayllar**: `backups\nssm-logs\backend.out.log` /
  `.err.log` (agent uchun `agent.out.log` / `.err.log`), hajm bo'yicha
  avtomatik rotatsiya bilan (disk to'lib qolmasligi uchun).

O'rnatishdan keyin qo'lda ishga tushirish/tekshirish:

```
nssm start KipTaroziBackend
nssm start KipTaroziAgent
Get-Service KipTaroziBackend, KipTaroziAgent
```

## 3. O'chirish

```
powershell -ExecutionPolicy Bypass -File scripts\nssm_ochirish.ps1
```

Skript avval **aniq "HA" deb yozishni** talab qiladi (tasodifan
ishga tushirilmasligi uchun) va faqat `KipTaroziBackend` /
`KipTaroziAgent` xizmatlarini to'xtatib, o'chiradi. Boshqa hech qanday
xizmatga tegilmaydi. Avtomatlashtirilgan (skriptdan ichki chaqiriladigan)
holatlar uchun tasdiqni chetlab o'tish kerak bo'lsa: `-Majburiy`.

## 4. Sozlamalarni keyinroq o'zgartirish

`nssm.exe`ning o'z GUI muharriri orqali (parametrsiz `nssm edit
KipTaroziBackend`) yoki `nssm set <xizmat> <parametr> <qiymat>` bilan
istalgan sozlamani (port, muhit o'zgaruvchilari va h.k.) keyinroq
o'zgartirish mumkin — buning uchun avval `.env` faylni yangilab, keyin
xizmatni qayta ishga tushirish kifoya (`nssm restart KipTaroziBackend`).

## 5. Real watchdog sinovi — natija (2026-09-10)

`KipTaroziAgent` xizmati shu kompyuterda (`C:\hazorasp_tarozi\nssm.exe`,
NSSM 2.24 64-bit) haqiqatan o'rnatilib, watchdog (avtomatik qayta ishga
tushirish) xususiyati REAL sinaldi — faqat `KipTaroziAgent` o'rnatildi,
`KipTaroziBackend` ATAYLAB o'rnatilmadi (chunki port 8000'da qo'lda
ishga tushirilgan dev-backend allaqachon ishlayotgan edi; skriptni
to'liq ishga tushirish ikkalasini ham o'rnatgan bo'lardi).

**Sinov bosqichlari va natija:**

1. O'rnatishdan oldin: `HazoraspBackend` (Stopped), `HazoraspFrontend`
   (Running) — holat yozib olindi.
2. `KipTaroziAgent` o'rnatildi (`nssm install` + `AppExit Default
   Restart`, `AppRestartDelay=3000ms`, `AppThrottle=1500ms`,
   `Start=SERVICE_AUTO_START`, loglar `backups\nssm-logs\agent.*.log`).
3. O'rnatishdan keyin: `HazoraspBackend`/`HazoraspFrontend` holati
   **o'zgarmadi** (hech qanday ta'sir yo'q), `KipTaroziBackend` xizmati
   **yaratilmadi**.
4. `Start-Service KipTaroziAgent` → `GET http://127.0.0.1:8100/holat` →
   `200 OK` (RS232/COM3 ulanmagani kutilgan — bu dev kompyuterda
   jismoniy tarozi yo'q, agentning o'zi sog'lom ishlayotgani muhim).
5. Watchdog sinovi — real jarayonni (NSSM emas, uning bola
   `python.exe` jarayonini) `Stop-Process -Force` bilan **3 marta**
   ketma-ket "o'ldirildi":

   | # | O'ldirilgan PID | ~5s dan keyin holat | Yangi PID | `/holat` |
   |---|---|---|---|---|
   | 1 | 13116 | Running | 22444 | 200 OK |
   | 2 | 22444 | Running | 21392 | 200 OK |
   | 3 | 21392 | Running | 13776 | 200 OK |

   Har safar: xizmat holati (`Get-Service`) uzluksiz **Running** bo'lib
   qoldi (chunki NSSM'ning o'zi — servis egasi jarayon — o'lmadi, faqat
   uning nazorat qilayotgan bola jarayoni o'ldirildi), va NSSM ~3
   soniya ichida yangi jarayonni ishga tushirdi (`agent.err.log`da har
   bitta qayta ishga tushirishda alohida "Started server process
   [PID]" yozuvi va "Uvicorn running on http://0.0.0.0:8100" tasdiqi
   bor).
6. Yakunda xizmat **Running** holatida qoldirildi (Automatic start) —
   productionga tayyor holatni ko'rsatish uchun ataylab shunday
   qoldirildi; agar kerak bo'lmasa `nssm stop KipTaroziAgent` yoki
   `scripts\nssm_ochirish.ps1` bilan o'chirish mumkin.

**Xulosa:** NSSM watchdog xususiyati haqiqiy Windows xizmati sifatida
kutilganidek ishlaydi — jarayon kutilmagan sababdan o'lsa (masalan
kip tarozi kompyuteri qayta ishga tushganda yoki agent qulab tushsa),
xizmat operator aralashuvisiz ~3 soniya ichida o'zi tiklanadi.

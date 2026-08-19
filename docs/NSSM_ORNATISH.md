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

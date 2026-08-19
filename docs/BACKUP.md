# PostgreSQL backup

Kunlik avtomatik backup uchun skript: [scripts/backup_yarat.ps1](../scripts/backup_yarat.ps1)

## Nima qiladi

1. `backend\.env` dagi `DATABASE_URL`'ni o'qiydi (host, port, foydalanuvchi,
   parol, baza nomi) — alohida joyda DB ma'lumotlarini takrorlash shart emas.
2. `pg_dump -F c` bilan to'liq backup oladi (custom format, `.dump`) va
   `C:\Kip_tarozi\backups\kip_tarozi_YYYY-MM-DD_HHmm.dump` nomi bilan saqlaydi.
3. Sozlangan bo'lsa, faylni tashqi joyga (`$BackupRemoteDir`) ham nusxalaydi.
4. `$RetentionDays`'dan (standart: 30 kun) eski `.dump` fayllarni mahalliy va
   (sozlangan bo'lsa) tashqi papkadan o'chiradi.
5. Har bir ishga tushishni `C:\Kip_tarozi\backups\logs\backup.log`'ga yozadi.

Xatolik bo'lsa skript exit code 1 bilan tugaydi (Task Scheduler shuni "muvaffaqiyatsiz" deb belgilashi uchun) va sababi log fayl + konsolga yoziladi.

## Sozlash

Sozlamalar `scripts\backup_config.ps1` faylida (bu fayl `.gitignore`'da —
har mashinada alohida, qo'lda yaratiladi):

```
Copy-Item scripts\backup_config.ps1.example scripts\backup_config.ps1
```

Keyin `backup_config.ps1`'ni oching va kerakli qiymatlarni kiriting:

- `$BackupLocalDir` — mahalliy backup papkasi (standart: `C:\Kip_tarozi\backups`).
- `$BackupRemoteDir` — **tashqi (ikkinchi) nusxa qayerga ko'chirilsin**.
  Hozircha aniq joy tanlanmagan bo'lsa, bo'sh (`""`) qoldiring — skript shunda
  faqat mahalliy backup bilan cheklanadi va har safar ogohlantirish yozadi.
  Joy tanlangach, shu yerga yozing, masalan:
  - boshqa mahalliy disk: `"D:\Backups\kip_tarozi"`
  - tarmoqdagi umumiy papka: `"\\SERVER\Backups\kip_tarozi"` (papka VPS
    hisobidan yozish huquqi bilan ochiq bo'lishi kerak)
  - bulutga sinxronlanadigan papka (OneDrive/Google Drive/Yandex Disk
    desktop ilovasi o'rnatilgan bo'lsa): shu ilova sinxronlaydigan mahalliy
    papka yo'li (masalan `"C:\Users\...\OneDrive\KipTaroziBackup"`)
- `$RetentionDays` — nechchi kundan eski fayllar o'chirilsin (standart: 30).
- `$PgBinDir` — odatda bo'sh qoldiriladi (skript PATH'dan va
  `C:\Program Files\PostgreSQL\*\bin`'dan avtomatik topadi); bir nechta
  PostgreSQL versiyasi o'rnatilgan bo'lsa aniq yo'lni shu yerga yozing.

## Qo'lda ishga tushirish / sinash

```
powershell -ExecutionPolicy Bypass -File scripts\backup_yarat.ps1
```

Muvaffaqiyatli bo'lsa `backups\` papkasida yangi `.dump` fayl paydo bo'ladi
va konsolda/`backups\logs\backup.log`'da "Backup muvaffaqiyatli yakunlandi"
deb chiqadi.

## Tiklashni sinash (restore test)

Backup'ning haqiqatan ishlashini vaqti-vaqti bilan tekshirish kerak — buning
uchun uni **asosiy bazaga emas**, alohida test bazasiga tiklang:

```
"C:\Program Files\PostgreSQL\18\bin\psql.exe" -h localhost -p 47432 -U postgres -d postgres -c "CREATE DATABASE kip_tarozi_restore_test;"
"C:\Program Files\PostgreSQL\18\bin\pg_restore.exe" -h localhost -p 47432 -U postgres -d kip_tarozi_restore_test "C:\Kip_tarozi\backups\kip_tarozi_2026-08-19_0902.dump"
```

Tekshirish uchun jadval qatorlari sonini solishtiring:

```
psql ... -d kip_tarozi -c "SELECT count(*) FROM kiplar;"
psql ... -d kip_tarozi_restore_test -c "SELECT count(*) FROM kiplar;"
```

So'ng test bazasini o'chiring: `DROP DATABASE kip_tarozi_restore_test;`

Haqiqiy avariya holatida (asosiy baza yo'qolgan/buzilgan) tiklash xuddi
shunday, faqat `-d kip_tarozi_restore_test` o'rniga to'g'ridan-to'g'ri (bo'sh)
`kip_tarozi` bazasiga qilinadi.

## Har kuni avtomatik ishga tushirish — Task Scheduler

Backup — kuniga bir marta ishlab tugaydigan qisqa vazifa, shuning uchun
**Windows Task Scheduler** to'g'ri vosita (NSSM doimiy ishlab turadigan
xizmatlar — backend, stansiya agenti — uchun mo'ljallangan, bir martalik
kunlik skript uchun emas).

### GUI orqali

1. `Task Scheduler` (Vazifalar rejalashtiruvchisi) dasturini oching.
2. **Create Task...** (Create Basic Task emas — to'liq sozlash uchun) tanlang.
3. **General**: nom — masalan `KipTarozi-Backup`. "Run whether user is
   logged on or not" tanlang. "Run with highest privileges" belgilang.
4. **Triggers** → **New** → Daily, xohlagan vaqt (masalan 03:00), Enabled.
5. **Actions** → **New**:
   - Program/script: `powershell.exe`
   - Add arguments:
     `-NoProfile -ExecutionPolicy Bypass -File "C:\Kip_tarozi\scripts\backup_yarat.ps1"`
   - Start in: `C:\Kip_tarozi`
6. **Conditions**: "Start the task only if the computer is on AC power"
   belgisini kompyuter turiga qarab o'chiring (serverlarda odatda kerak
   emas).
7. **Settings**: "If the task fails, restart every" — masalan 10 daqiqa,
   3 marta — vaqtinchalik xatolarga (masalan Postgres hali ishga
   tushmagan bo'lsa) chidamli bo'lishi uchun.
8. Saqlashda administrator hisobi parolini so'raydi (agar shunday hisob
   tanlangan bo'lsa).

### Buyruq qatori orqali (schtasks)

Administrator sifatida PowerShell'da:

```
schtasks /Create /TN "KipTarozi-Backup" /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:\Kip_tarozi\scripts\backup_yarat.ps1\"" /SC DAILY /ST 03:00 /RU SYSTEM /RL HIGHEST
```

- `/RU SYSTEM` — SYSTEM hisobi ostida ishlaydi (foydalanuvchi login
  qilmagan bo'lsa ham ishlayveradi). Agar `C:\Kip_tarozi\backups` yoki
  `$BackupRemoteDir` (tarmoq papkasi) uchun boshqa hisobning huquqi kerak
  bo'lsa, `/RU domain\user /RP parol` bilan almashtiring.
- Sinash: `schtasks /Run /TN "KipTarozi-Backup"`, keyin
  `backups\logs\backup.log`'ni tekshiring.
- O'chirish (kerak bo'lsa): `schtasks /Delete /TN "KipTarozi-Backup" /F`

### Muhim eslatma

Vazifa `/RU SYSTEM` yoki boshqa xizmat hisobi ostida ishlasa va
`$BackupRemoteDir` tarmoq papkasi (`\\SERVER\...`) bo'lsa, o'sha hisobning
tarmoq papkasiga yozish huquqi borligini alohida tekshiring — SYSTEM hisobi
odatda tarmoq resurslariga kira olmaydi. Bunday holatda alohida xizmat
hisobi (`/RU domain\backup_user /RP ...`) yarating.

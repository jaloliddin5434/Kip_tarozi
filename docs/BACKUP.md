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

Backup'ning haqiqatan ishlashini oyiga bir marta tekshirib turing — tiklashni
**asosiy `kip_tarozi` bazasiga emas**, alohida vaqtinchalik test bazasiga qiling.
Quyidagi 4 qadam asl bazaga hech narsa yozmaydi (faqat undan `pg_dump` bilan
o'qiydi va `count(*)` bilan solishtiradi).

PowerShell'da (bir sessiyada ketma-ket):

```powershell
$PG   = "C:\Program Files\PostgreSQL\18\bin"      # pg_dump / pg_restore / psql bin papkasi
$PORT = 47432
$TESTDB = "kip_tarozi_restore_test"

# 1) Yangi backup (yoki mavjud eng so'nggi .dump'ni ol)
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Kip_tarozi\scripts\backup_yarat.ps1
$DUMP = (Get-ChildItem C:\Kip_tarozi\backups\kip_tarozi_*.dump | Sort-Object LastWriteTime -Desc)[0].FullName
"Tiklanadigan fayl: $DUMP"
& "$PG\pg_restore.exe" --list $DUMP | Select-String "Format|dbname|Dumped from"   # fayl butunligini tekshir

# 2) Vaqtinchalik test bazasi yarat va unga tikla
& "$PG\psql.exe"       -h localhost -p $PORT -U postgres -d postgres -c "CREATE DATABASE $TESTDB;"
& "$PG\pg_restore.exe" -h localhost -p $PORT -U postgres -d $TESTDB --no-owner --exit-on-error $DUMP
"pg_restore exit code (0 bo'lishi kerak): $LASTEXITCODE"

# 3) Har bir jadval qatorlari sonini asl baza bilan solishtir
$sql = @"
SELECT 'kiplar' t,count(*) n FROM kiplar
UNION ALL SELECT 'partiyalar',count(*) FROM partiyalar
UNION ALL SELECT 'foydalanuvchilar',count(*) FROM foydalanuvchilar
UNION ALL SELECT 'mahsulotlar',count(*) FROM mahsulotlar
UNION ALL SELECT 'sozlamalar',count(*) FROM sozlamalar
UNION ALL SELECT 'audit_log',count(*) FROM audit_log
UNION ALL SELECT 'shubhali_holatlar',count(*) FROM shubhali_holatlar
UNION ALL SELECT 'stansiyalar',count(*) FROM stansiyalar ORDER BY t;
"@
"--- ASL kip_tarozi ---"
& "$PG\psql.exe" -h localhost -p $PORT -U postgres -d kip_tarozi -c $sql
"--- TIKLANGAN $TESTDB ---"
& "$PG\psql.exe" -h localhost -p $PORT -U postgres -d $TESTDB -c $sql
# Har bir qatordagi son ikkala ro'yxatda AYNAN bir xil bo'lishi SHART.

# 4) Test bazasini o'chir — hech qanday iz qoldirmaydi
& "$PG\psql.exe" -h localhost -p $PORT -U postgres -d postgres -c "DROP DATABASE $TESTDB;"
```

`pg_restore` "already exists" / "constraint ... multiple primary keys" kabi
xatolar bersa — test bazasi bo'sh emas edi: uni `DROP DATABASE` qilib qaytadan
`CREATE DATABASE` qiling. `--exit-on-error` bo'lgani uchun jiddiy xato bo'lsa
`pg_restore` exit code 1 qaytaradi.

## Haqiqiy avariya holatida tiklash (asosiy baza yo'qolgan/buzilgan)

Xuddi yuqoridagi kabi, faqat test bazasiga emas — **bo'sh `kip_tarozi`**
bazasiga tiklanadi:

```powershell
$PG = "C:\Program Files\PostgreSQL\18\bin"; $PORT = 47432
# 0) Backend/agent xizmatlarini to'xtatib turing (bazaga yozmasin):
#    nssm stop KipTarozi-Backend   (yoki Task Manager orqali)

# 1) Eng so'nggi ishonchli backup faylni tanlang
$DUMP = (Get-ChildItem C:\Kip_tarozi\backups\kip_tarozi_*.dump | Sort-Object LastWriteTime -Desc)[0].FullName

# 2) Buzilgan bazani o'chirib, bo'sh qayta yarating
#    (agar baza umuman yo'qolgan bo'lsa — 2-qadamning faqat CREATE qismi)
& "$PG\psql.exe" -h localhost -p $PORT -U postgres -d postgres -c "DROP DATABASE IF EXISTS kip_tarozi;"
& "$PG\psql.exe" -h localhost -p $PORT -U postgres -d postgres -c "CREATE DATABASE kip_tarozi OWNER postgres;"

# 3) Backup'ni tiklang
& "$PG\pg_restore.exe" -h localhost -p $PORT -U postgres -d kip_tarozi --no-owner --exit-on-error $DUMP

# 4) Tekshiring va xizmatlarni qayta ishga tushiring
& "$PG\psql.exe" -h localhost -p $PORT -U postgres -d kip_tarozi -c "SELECT count(*) FROM kiplar;"
#    nssm start KipTarozi-Backend
```

> Backup faqat `pg_dump` olingan **paytgacha** bo'lgan ma'lumotni tiklaydi —
> oxirgi backupdan keyingi kiplar yo'qoladi. Shuning uchun backup har kuni
> avtomatik olinishi va `$BackupRemoteDir` (tashqi nusxa) sozlangan bo'lishi
> muhim.

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

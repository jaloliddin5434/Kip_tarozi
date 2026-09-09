# Backup (baza + fayllar)

Kunlik avtomatik backup uchun skript: [scripts/backup_yarat.ps1](../scripts/backup_yarat.ps1)

## Nima qiladi

1. `backend\.env` dagi `DATABASE_URL`'ni o'qiydi (host, port, foydalanuvchi,
   parol, baza nomi) — alohida joyda DB ma'lumotlarini takrorlash shart emas.
2. `pg_dump -F c` bilan **baza**ning to'liq backup'ini oladi (custom format,
   `.dump`) va `C:\Kip_tarozi\backups\kip_tarozi_YYYY-MM-DD_HHmm.dump` nomi
   bilan saqlaydi.
3. **`STORAGE_PATH` papkasini** (`backend\.env` dan; kamera suratlari
   `storage\<oy>\...` va nakladnoy PDF'lari `storage\nakladnoy\`) siqishsiz,
   sana bilan nomlangan `storage_YYYY-MM-DD_HHmm\` papkasiga fayl-fayl to'liq
   nusxalaydi. Har fayl alohida ko'chiriladi — ayni damda yozilayotgan/qulflangan
   fayl (surat, agent SQLite navbati) o'tkazib yuboriladi, qolgan nusxa
   buzilmaydi. `-SkipStorage` bilan yoki `$BackupStorage = $false` bilan bu
   qadam o'chiriladi.
   *(Excel/PDF hisobotlar — smena/mavsum Excel'i — foydalanuvchiga
   to'g'ridan-to'g'ri yuklab beriladi, diskda saqlanmaydi, shuning uchun
   ular backupsiz — faqat `storage\nakladnoy\` dagi nakladnoy PDF'lari
   diskda turadi va nusxaga kiradi.)*
4. Baza `.dump`'i va storage `storage_...\` papkasi — ikkalasi ham, sozlangan
   bo'lsa, tashqi joyga (`$BackupRemoteDir`) ham nusxalanadi.
5. `$RetentionDays`'dan (standart: 30 kun) eski `.dump` fayllar **va**
   `storage_*\` nusxa papkalarini mahalliy va (sozlangan bo'lsa) tashqi joydan
   o'chiradi.
6. Har bir ishga tushishni `C:\Kip_tarozi\backups\logs\backup.log`'ga yozadi.

**Baza** backup'i xato bilan tugasa — skript exit code 1 bilan tugaydi
(Task Scheduler "muvaffaqiyatsiz" deb belgilaydi). **Storage** zaxirasi xato
bersa — baza `.dump`'i baribir saqlanadi, skript exit code 0 bilan tugaydi,
lekin `backup.log`'ga ko'zga tashlanadigan `WARN` yoziladi ("storage zaxirasi
MUVAFFAQIYATSIZ"). Shuning uchun `backup.log`'ni faqat exit code emas,
`WARN`/`ERROR` qatorlari bo'yicha ham kuzatib turing.

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
- `$RetentionDays` — nechchi kundan eski `.dump` fayllar va `storage_*\` nusxa
  papkalari o'chirilsin (standart: 30).
- `$PgBinDir` — odatda bo'sh qoldiriladi (skript PATH'dan va
  `C:\Program Files\PostgreSQL\*\bin`'dan avtomatik topadi); bir nechta
  PostgreSQL versiyasi o'rnatilgan bo'lsa aniq yo'lni shu yerga yozing.
- `$BackupStorage` — `storage\` papkasini (suratlar + nakladnoy PDF) ham
  zaxiralash. Standart `$true`. Faqat bazani zaxiralash kifoya bo'lsa
  `$false` qiling (yoki skriptni bir martaga `-SkipStorage` bilan chaqiring).
- `$StorageWarnGB` — `storage\` shu hajmdan (GB) oshsa `backup.log`'ga
  ogohlantirish yoziladi (standart: 5). Pastdagi "Katta storage papkasi"ga
  qarang.

## Qo'lda ishga tushirish / sinash

```
powershell -ExecutionPolicy Bypass -File scripts\backup_yarat.ps1
```

Muvaffaqiyatli bo'lsa `backups\` papkasida yangi `kip_tarozi_*.dump` fayli
**va** `storage_*\` nusxa papkasi paydo bo'ladi va `backups\logs\backup.log`'da
"Backup muvaffaqiyatli yakunlandi" deb chiqadi.

Faqat bazani (storage'siz) olish:

```
powershell -ExecutionPolicy Bypass -File scripts\backup_yarat.ps1 -SkipStorage
```

## Katta storage papkasi (disk joyi)

Har kunlik zaxira — `storage\` papkasining **to'liq nusxasi** (inkremental
emas). 30 kun saqlansa, `backups\` da `storage\` joriy hajmining ~30 barobari
band bo'ladi.

Joriy hisob-kitob: `storage\` ~62 MB atrofida → 30 kunlik saqlash ~1.85 GB.
Bu tashvishga o'rin qoldirmaydi. Mavsum davomida papka biroz o'ssa ham
(suratlar ~250–300 KB/dona) hajm bir necha GB'dan oshmaydi.

Agar kelajakda `storage\` kutilmaganda juda kattalashsa (`$StorageWarnGB`,
standart 5 GB, dan oshganda skript `backup.log`'ga `OGOHLANTIRISH` yozadi) —
quyidagilardan birini tanlang:

- **`$RetentionDays`'ni kamaytiring** — hozircha bitta qiymat `.dump` va
  storage nusxalariga birga amal qiladi; alohida kerak bo'lsa ayting, skript
  kengaytiriladi.
- **`$BackupStorage = $false`** qiling va `storage\` ni alohida, faqat yangi
  fayllarni qo'shadigan mirror bilan himoyalang (har safar bir necha soniya,
  lekin "sana bo'yicha snapshot" bermaydi):
  ```
  robocopy "C:\Kip_tarozi\storage" "D:\Backups\storage_mirror" /E /XO /R:1 /W:2 /NFL /NDL /NP
  ```
- **Eski oylarni arxivlab, `storage\` dan olib tashlang** (masalan mavsum
  tugagach `storage\2025-09\` ni alohida uzoq muddatli arxivga ko'chiring).

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

# 1) Yangi backup (yoki mavjud eng so'nggi .dump'ni ol).
#    Restore testiga faqat baza kerak — storage nusxasini o'tkazib yuboramiz (-SkipStorage).
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Kip_tarozi\scripts\backup_yarat.ps1 -SkipStorage
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

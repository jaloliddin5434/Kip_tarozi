<#
    Kip Tarozi - tezkor (engil) Excel+surat yangilanishi.

    Kuniga UCH MARTA, aniq vaqtda ishga tushirish uchun mo'ljallangan
    (Task Scheduler: 08:10, 16:10, 00:10 - qarang docs\BACKUP.md). Kechqurungi
    TO'LIQ backup (scripts\backup_yarat.ps1, 03:00, baza dump + storage xom
    nusxa + tushunarli tuzilma, kunlar bo'yicha saqlanadigan tarixiy
    nusxalar bilan) O'RNIGA EMAS - unga QO'SHIMCHA, tezkor "eng so'nggi
    holat" sinxroni:

      - Baza HECH QACHON dump qilinmaydi.
      - Storage'ning "xom" (hash nomli) to'liq nusxasi OLINMAYDI.
      - Faqat backend\scripts\backup_tuzilma.py orqali "tushunarli tuzilma"
        (KIP-Tarozi Rasm / Excel / Nakladnoy) bazadan REAL O'QIB qayta
        yasaladi - MAHALLIY YAGONA, vaqt-belgisiz papkaga
        (C:\Kip_tarozi\backups\tezkor_yangilanish\), HAR SAFAR eskisi
        o'chirilib ustidan yoziladi (tarixiy nusxalar to'planmaydi - bu
        backup emas, faqat "eng so'nggi holat" ko'rinishi).
      - Shu YAGONA papka tashqi zaxira kompyuteriga ($BackupRemoteDir,
        scripts\backup_config.ps1) xuddi shunday nomi bilan (bitta
        "tezkor_yangilanish" papkasi, tashqi joyda ham ustidan yozilib)
        ko'chiriladi.

    Umumiy funksiyalar (Write-BackupLog, Invoke-BackupTuzilma,
    Copy-ToRemoteFolder) backup_yarat.ps1 bilan baham ko'rilgan - qarang
    backup_common.ps1 (kod takrorlanmasin).

    Tashqi zaxira kompyuter/tarmoq papkasi ayni damda mavjud bo'lmasa -
    skript XATO BILAN TO'XTAMAYDI: WARN yoziladi, mahalliy nusxa baribir
    saqlangan bo'ladi, keyingi ishga tushishda qayta uriniladi. Faqat
    "tushunarli tuzilma"ning o'zi (bazadan o'qish/Excel yasash)
    muvaffaqiyatsiz bo'lsa - skript bu holda haqiqatan hech narsa
    bajarmagan bo'ladi, shuning uchun exit code 1 bilan tugaydi.

    Ishga tushirish:  powershell -ExecutionPolicy Bypass -File scripts\tezkor_yangilash.ps1
    Sozlamalar:        scripts\backup_config.ps1 ($BackupRemoteDir) - backup_yarat.ps1 bilan bir xil fayl.
    To'liq yo'riqnoma: docs\BACKUP.md
#>

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

# Umumiy funksiyalar - qarang backup_common.ps1.
. (Join-Path $ScriptDir "backup_common.ps1")

# --- Sozlamalarni yuklash (faqat $BackupRemoteDir kerak, boshqa
# --- qiymatlar - $RetentionDays, $BackupStorage va h.k. - bu skriptga
# --- aloqasi yo'q, chunki bitta ustidan-yoziladigan papka bilan ishlaydi). ---
$BackupLocalDir = "C:\Kip_tarozi\backups"
$BackupRemoteDir = ""

$ConfigFile = Join-Path $ScriptDir "backup_config.ps1"
if (Test-Path $ConfigFile) {
    . $ConfigFile
}

$TezkorLocalDir = Join-Path $BackupLocalDir "tezkor_yangilanish"
$LogDir = Join-Path $BackupLocalDir "logs"
New-Item -ItemType Directory -Force -Path $BackupLocalDir | Out-Null
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir "tezkor_yangilash.log"

try {
    Write-BackupLog -LogFile $LogFile -Message "Tezkor yangilash boshlandi."

    if (Test-Path -LiteralPath $TezkorLocalDir) {
        Remove-Item -LiteralPath $TezkorLocalDir -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $TezkorLocalDir | Out-Null

    Invoke-BackupTuzilma -Root $ProjectRoot -Dest $TezkorLocalDir -LogFile $LogFile
    Write-BackupLog -LogFile $LogFile -Message "Mahalliy tushunarli tuzilma tayyor: $TezkorLocalDir (KIP-Tarozi Rasm / Excel / Nakladnoy)"

    Copy-ToRemoteFolder -LocalDir $TezkorLocalDir -RemoteDir $BackupRemoteDir -Name "tezkor_yangilanish" -LogFile $LogFile | Out-Null

    Write-BackupLog -LogFile $LogFile -Message "Tezkor yangilash muvaffaqiyatli yakunlandi."
    exit 0
} catch {
    Write-BackupLog -LogFile $LogFile -Message "XATO: $($_.Exception.Message)" -Level "ERROR"
    exit 1
}

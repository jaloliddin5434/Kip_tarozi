<#
    Kip Tarozi - test-ma'lumotlarni tozalash skripti.

    Haqiqiy mavsum boshlanishidan oldin bazani nolga qaytarish uchun:
    kiplar, partiyalar, audit_log, shubhali_holatlar jadvallaridagi BARCHA
    yozuvlarni butunlay o'chiradi (id ketma-ketliklari ham 1'dan qayta
    boshlanadi).

    Foydalanuvchilar, mahsulotlar, stansiyalar, sozlamalar jadvallariga
    TEGMAYDI.

    Xavfsizlik:
      - Ishga tushirishdan oldin aniq ogohlantirish ko'rsatadi va foydalanuvchi
        qo'lda "HA" deb yozmaguncha davom etmaydi.
      - Tozalashdan oldin scripts\backup_yarat.ps1 orqali avtomatik backup
        oladi; backup muvaffaqiyatsiz tugasa, tozalash BOSHLANMAYDI.

    Ishga tushirish: powershell -ExecutionPolicy Bypass -File scripts\malumotlarni_tozalash.ps1
    To'liq yo'riqnoma: docs\MALUMOTLARNI_TOZALASH.md
#>

param(
    # Ixtiyoriy: berilsa, backend\.env dagi DATABASE_URL o'rniga shu qiymat
    # ishlatiladi. FAQAT sinov/rivojlantirish uchun - haqiqiy ma'lumotlarni
    # tozalashda bu parametrni BERMANG, skript backend\.env'ni o'zi o'qiydi.
    [string]$DatabaseUrl
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$EnvFile = Join-Path $ProjectRoot "backend\.env"
$BackupScript = Join-Path $ScriptDir "backup_yarat.ps1"

$PgBinDir = ""
$ConfigFile = Join-Path $ScriptDir "backup_config.ps1"
if (Test-Path $ConfigFile) {
    . $ConfigFile
}

function Find-PgBin {
    param([string]$ToolName)

    if ($PgBinDir -and (Test-Path (Join-Path $PgBinDir "$ToolName.exe"))) {
        return (Join-Path $PgBinDir "$ToolName.exe")
    }

    $onPath = Get-Command "$ToolName.exe" -ErrorAction SilentlyContinue
    if ($onPath) {
        return $onPath.Source
    }

    $candidates = Get-ChildItem "C:\Program Files\PostgreSQL\*\bin\$ToolName.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending
    if ($candidates) {
        return $candidates[0].FullName
    }

    return $null
}

# O'chiriladigan jadvallar - kiplar avval (partiyalarga bog'liq), keyin
# partiyalar, keyin audit_log va shubhali_holatlar (bog'liqliksiz).
$TozalanadiganJadvallar = @("kiplar", "partiyalar", "audit_log", "shubhali_holatlar")
$TegilmaydiganJadvallar = @("foydalanuvchilar", "mahsulotlar", "stansiyalar", "sozlamalar")

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Red
Write-Host " DIQQAT: bu barcha tortish ma'lumotlarini butunlay o'chiradi," -ForegroundColor Red
Write-Host "         QAYTARIB BO'LMAYDI!" -ForegroundColor Red
Write-Host "==================================================================" -ForegroundColor Red
Write-Host ""
Write-Host "O'chiriladigan jadvallar (barcha qatorlar, id'lar 1'dan qayta boshlanadi):"
foreach ($t in $TozalanadiganJadvallar) { Write-Host "  - $t" -ForegroundColor Yellow }
Write-Host ""
Write-Host "TEGILMAYDIGAN jadvallar (saqlanib qoladi):"
foreach ($t in $TegilmaydiganJadvallar) { Write-Host "  - $t" -ForegroundColor Green }
Write-Host ""
Write-Host "Davom etishdan oldin avtomatik backup olinadi (scripts\backup_yarat.ps1)."
Write-Host ""

$javob = Read-Host "Davom etish uchun aniq 'HA' deb yozing (boshqa har qanday javob bekor qiladi)"
if ($javob -cne "HA") {
    Write-Host "Bekor qilindi - hech narsa o'chirilmadi." -ForegroundColor Cyan
    exit 1
}

try {
    Write-Host ""
    Write-Host "1/2: Tozalashdan oldin backup olinmoqda ..." -ForegroundColor Cyan
    if ($DatabaseUrl) {
        & $BackupScript -DatabaseUrl $DatabaseUrl
    } else {
        & $BackupScript
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Backup muvaffaqiyatsiz tugadi (exit code $LASTEXITCODE) - xavfsizlik uchun tozalash BOSHLANMAYDI."
    }

    Write-Host ""
    Write-Host "2/2: Ma'lumotlar tozalanmoqda ..." -ForegroundColor Cyan

    if ($DatabaseUrl) {
        $resolvedUrl = $DatabaseUrl
    } else {
        if (-not (Test-Path $EnvFile)) {
            throw "backend\.env topilmadi: $EnvFile"
        }
        $line = (Get-Content $EnvFile) | Where-Object { $_ -match '^\s*DATABASE_URL\s*=' } | Select-Object -First 1
        if (-not $line) {
            throw "backend\.env ichida DATABASE_URL topilmadi."
        }
        $resolvedUrl = ($line -split '=', 2)[1].Trim()
    }

    $pattern = '^postgresql(\+\w+)?://(?<user>[^:@/]+)(:(?<pass>[^@]*))?@(?<host>[^:/]+)(:(?<port>\d+))?/(?<db>[^?\s]+)'
    $m = [regex]::Match($resolvedUrl, $pattern)
    if (-not $m.Success) {
        throw "DATABASE_URL formatini tushunib bo'lmadi: $resolvedUrl"
    }

    $dbUser = $m.Groups['user'].Value
    $dbPass = $m.Groups['pass'].Value
    $dbHostName = $m.Groups['host'].Value
    $dbPort = if ($m.Groups['port'].Success) { $m.Groups['port'].Value } else { "5432" }
    $dbName = $m.Groups['db'].Value

    $psql = Find-PgBin "psql"
    if (-not $psql) {
        throw "psql.exe topilmadi. PATH'ga qo'shing yoki scripts\backup_config.ps1'da `$PgBinDir'ni ko'rsating."
    }

    $sql = "TRUNCATE TABLE " + ($TozalanadiganJadvallar -join ", ") + " RESTART IDENTITY;"

    $env:PGPASSWORD = $dbPass
    try {
        & $psql -h $dbHostName -p $dbPort -U $dbUser -d $dbName -v ON_ERROR_STOP=1 -c $sql
        $sqlExit = $LASTEXITCODE
    } finally {
        Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue
    }

    if ($sqlExit -ne 0) {
        throw "Tozalash SQL xato bilan tugadi (exit code $sqlExit)."
    }

    Write-Host ""
    Write-Host "Tozalandi: $($TozalanadiganJadvallar -join ', ')" -ForegroundColor Green
    Write-Host "Tegilmadi: $($TegilmaydiganJadvallar -join ', ')" -ForegroundColor Green
    exit 0
} catch {
    Write-Host ""
    Write-Host "XATO: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

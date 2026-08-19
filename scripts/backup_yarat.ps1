<#
    Kip Tarozi - kunlik PostgreSQL backup skripti.

    backend\.env dagi DATABASE_URL'dan baza ulanish ma'lumotlarini o'qiydi,
    pg_dump bilan to'liq backup oladi (custom format, .dump), uni mahalliy
    papkaga yozadi, sozlangan bo'lsa tashqi joyga ham nusxalaydi va
    $RetentionDays'dan eski fayllarni o'chiradi.

    Ishga tushirish: powershell -ExecutionPolicy Bypass -File scripts\backup_yarat.ps1
    Sozlamalar: scripts\backup_config.ps1 (namuna: backup_config.ps1.example)
    To'liq yo'riqnoma: docs\BACKUP.md
#>

param(
    # Ixtiyoriy: berilsa, backend\.env dagi DATABASE_URL o'rniga shu qiymat
    # ishlatiladi (masalan boshqa skriptdan sinov bazasi uchun chaqirilganda).
    [string]$DatabaseUrl
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$EnvFile = Join-Path $ProjectRoot "backend\.env"

# --- Sozlamalarni yuklash (config fayl bo'lmasa standart qiymatlar) ---
$BackupLocalDir = "C:\Kip_tarozi\backups"
$BackupRemoteDir = ""
$RetentionDays = 30
$PgBinDir = ""

$ConfigFile = Join-Path $ScriptDir "backup_config.ps1"
if (Test-Path $ConfigFile) {
    . $ConfigFile
} else {
    Write-Warning "scripts\backup_config.ps1 topilmadi - standart qiymatlar ishlatiladi (faqat mahalliy backup, $RetentionDays kun saqlash). Namuna: scripts\backup_config.ps1.example"
}

$LogDir = Join-Path $BackupLocalDir "logs"
New-Item -ItemType Directory -Force -Path $BackupLocalDir | Out-Null
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir "backup.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
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

function Remove-OldBackups {
    param([string]$Dir, [int]$Days)

    if (-not (Test-Path $Dir)) { return }
    $threshold = (Get-Date).AddDays(-$Days)
    $old = Get-ChildItem -Path $Dir -Filter "kip_tarozi_*.dump" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $threshold }
    foreach ($f in $old) {
        try {
            Remove-Item $f.FullName -Force
            Write-Log "Eski backup o'chirildi: $($f.FullName)"
        } catch {
            Write-Log "Eski backupni o'chirib bo'lmadi: $($f.FullName) - $($_.Exception.Message)" "WARN"
        }
    }
}

try {
    Write-Log "Backup boshlandi."

    if ($DatabaseUrl) {
        $databaseUrl = $DatabaseUrl
    } else {
        if (-not (Test-Path $EnvFile)) {
            throw "backend\.env topilmadi: $EnvFile"
        }

        $databaseUrl = (Get-Content $EnvFile) | Where-Object { $_ -match '^\s*DATABASE_URL\s*=' } | Select-Object -First 1
        if (-not $databaseUrl) {
            throw "backend\.env ichida DATABASE_URL topilmadi."
        }
        $databaseUrl = ($databaseUrl -split '=', 2)[1].Trim()
    }

    # postgresql(+driver)://user[:pass]@host[:port]/dbname
    $pattern = '^postgresql(\+\w+)?://(?<user>[^:@/]+)(:(?<pass>[^@]*))?@(?<host>[^:/]+)(:(?<port>\d+))?/(?<db>[^?\s]+)'
    $m = [regex]::Match($databaseUrl, $pattern)
    if (-not $m.Success) {
        throw "DATABASE_URL formatini tushunib bo'lmadi: $databaseUrl"
    }

    $dbUser = $m.Groups['user'].Value
    $dbPass = $m.Groups['pass'].Value
    $dbHost = $m.Groups['host'].Value
    $dbPort = if ($m.Groups['port'].Success) { $m.Groups['port'].Value } else { "5432" }
    $dbName = $m.Groups['db'].Value

    $pgDump = Find-PgBin "pg_dump"
    if (-not $pgDump) {
        throw "pg_dump.exe topilmadi. PATH'ga qo'shing yoki scripts\backup_config.ps1'da `$PgBinDir'ni ko'rsating."
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd_HHmm"
    $fileName = "kip_tarozi_${timestamp}.dump"
    $localPath = Join-Path $BackupLocalDir $fileName

    Write-Log "Baza: $dbName@${dbHost}:${dbPort} (foydalanuvchi: $dbUser)"
    Write-Log "pg_dump: $pgDump"
    Write-Log "Fayl: $localPath"

    $env:PGPASSWORD = $dbPass
    try {
        & $pgDump -h $dbHost -p $dbPort -U $dbUser -d $dbName -F c -f $localPath 2>&1 |
            ForEach-Object { Write-Log $_ }
        $dumpExit = $LASTEXITCODE
    } finally {
        Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue
    }

    if ($dumpExit -ne 0) {
        throw "pg_dump xato bilan tugadi (exit code $dumpExit)."
    }
    if (-not (Test-Path $localPath) -or (Get-Item $localPath).Length -eq 0) {
        throw "Backup fayl yaratilmadi yoki bo'sh: $localPath"
    }

    $sizeKb = [math]::Round((Get-Item $localPath).Length / 1KB, 1)
    Write-Log "Mahalliy backup tayyor: $localPath ($sizeKb KB)"

    if ($BackupRemoteDir) {
        try {
            if (-not (Test-Path $BackupRemoteDir)) {
                New-Item -ItemType Directory -Force -Path $BackupRemoteDir | Out-Null
            }
            $remotePath = Join-Path $BackupRemoteDir $fileName
            Copy-Item -Path $localPath -Destination $remotePath -Force
            Write-Log "Tashqi nusxa ko'chirildi: $remotePath"
        } catch {
            Write-Log "Tashqi joyga nusxalashda xato: $($_.Exception.Message)" "WARN"
        }
    } else {
        Write-Log "BackupRemoteDir sozlanmagan - faqat mahalliy backup saqlandi (docs\BACKUP.md'ga qarang)." "WARN"
    }

    Remove-OldBackups -Dir $BackupLocalDir -Days $RetentionDays
    if ($BackupRemoteDir -and (Test-Path $BackupRemoteDir)) {
        Remove-OldBackups -Dir $BackupRemoteDir -Days $RetentionDays
    }

    Write-Log "Backup muvaffaqiyatli yakunlandi."
    exit 0
} catch {
    Write-Log "XATO: $($_.Exception.Message)" "ERROR"
    exit 1
}

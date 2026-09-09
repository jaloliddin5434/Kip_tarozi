<#
    Kip Tarozi - kunlik backup skripti.

    1) backend\.env dagi DATABASE_URL'dan baza ulanish ma'lumotlarini o'qiydi,
       pg_dump bilan to'liq baza backup'ini oladi (custom format, .dump).
    2) backend\.env dagi STORAGE_PATH papkasini (kamera suratlari + nakladnoy
       PDF'lari) sana bilan nomlangan papkaga to'liq nusxalaydi (siqishsiz,
       fayl-fayl: storage_YYYY-MM-DD_HHmm\). -SkipStorage berilsa yoki
       $BackupStorage = $false bo'lsa - o'tkazib yuboriladi.
    3) Ikkalasini ($BackupLocalDir'ga) yozadi, $BackupRemoteDir sozlangan
       bo'lsa - o'sha tarmoq joyiga ham ko'chiradi.
    4) $RetentionDays'dan (standart: 30 kun) eski .dump fayllar VA storage
       nusxa papkalarini mahalliy va (sozlangan bo'lsa) tashqi joydan o'chiradi.
    5) Har bir ishga tushishni C:\Kip_tarozi\backups\logs\backup.log'ga yozadi.

    Ishga tushirish:  powershell -ExecutionPolicy Bypass -File scripts\backup_yarat.ps1
    Faqat baza:       ... -File scripts\backup_yarat.ps1 -SkipStorage
    Sozlamalar:       scripts\backup_config.ps1 (namuna: backup_config.ps1.example)
    To'liq yo'riqnoma: docs\BACKUP.md

    Baza backup'i muvaffaqiyatsiz bo'lsa - skript exit code 1 bilan tugaydi
    (Task Scheduler "muvaffaqiyatsiz" deb belgilashi uchun). Storage zaxirasi
    muvaffaqiyatsiz bo'lsa - baza .dump'i baribir saqlanadi, skript exit 0
    bilan tugaydi, lekin backup.log'ga ko'zga tashlanadigan WARN yoziladi.
#>

param(
    # Ixtiyoriy: berilsa, backend\.env dagi DATABASE_URL o'rniga shu qiymat
    # ishlatiladi (masalan boshqa skriptdan sinov bazasi uchun chaqirilganda).
    [string]$DatabaseUrl,

    # Berilsa, storage/ papkasi zaxiralanmaydi (faqat baza .dump'i olinadi) -
    # masalan restore-test faqat bazani tekshirganda katta nusxa shart emas.
    [switch]$SkipStorage
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
$BackupStorage = $true      # storage/ papkasini (suratlar + nakladnoy PDF) ham zaxiralash (papka nusxasi)
$StorageWarnGB = 5          # storage shu hajmdan (GB) oshsa backup.log'da ogohlantirish

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
    # $Folder berilsa - fayllar emas, papkalar (masalan storage_* nusxalari) tozalanadi.
    param([string]$Dir, [int]$Days, [string]$Filter = "kip_tarozi_*.dump", [switch]$Folder)

    if (-not (Test-Path $Dir)) { return }
    $threshold = (Get-Date).AddDays(-$Days)
    $wantContainer = [bool]$Folder
    $old = Get-ChildItem -Path $Dir -Filter $Filter -ErrorAction SilentlyContinue |
        Where-Object { $_.PSIsContainer -eq $wantContainer -and $_.LastWriteTime -lt $threshold }
    foreach ($f in $old) {
        try {
            Remove-Item $f.FullName -Recurse -Force
            Write-Log "Eski backup o'chirildi: $($f.FullName)"
        } catch {
            Write-Log "Eski backupni o'chirib bo'lmadi: $($f.FullName) - $($_.Exception.Message)" "WARN"
        }
    }
}

function Get-StorageDir {
    # STORAGE_PATH'ni backend\.env'dan oladi; topilmasa <ProjectRoot>\storage.
    if (Test-Path $EnvFile) {
        $line = (Get-Content $EnvFile) | Where-Object { $_ -match '^\s*STORAGE_PATH\s*=' } | Select-Object -First 1
        if ($line) {
            $p = ($line -split '=', 2)[1].Trim().Trim('"').Trim("'")
            if ($p) { return ($p -replace '/', '\') }
        }
    }
    return (Join-Path $ProjectRoot "storage")
}

function Copy-StorageFolder {
    <#
        $SourceDir tarkibini (rekursiv) $DestDir ichiga fayl-fayl nusxalaydi
        (siqishsiz, papka tuzilishini saqlab). Har bir fayl ALOHIDA try/catch
        ichida - bittasi qulflangan/o'qib bo'lmaydigan bo'lsa (masalan ayni
        damda yozilayotgan surat yoki agent SQLite navbati), u O'TKAZIB
        yuboriladi, qolgan nusxa buzilmaydi. $ExcludePrefix bilan boshlanadigan
        yo'llar (masalan backups papkasining o'zi) nusxalanmaydi.
        Natija: nusxalangan/o'tkazilgan fayl soni + nusxalanganlar umumiy hajmi.
    #>
    param([string]$SourceDir, [string]$DestDir, [string]$ExcludePrefix = "")

    $base = (Resolve-Path -LiteralPath $SourceDir).Path.TrimEnd('\') + '\'
    $exclude = if ($ExcludePrefix -and (Test-Path -LiteralPath $ExcludePrefix)) {
        (Resolve-Path -LiteralPath $ExcludePrefix).Path
    } else { $null }
    $files = @(Get-ChildItem -LiteralPath $SourceDir -Recurse -File -Force -ErrorAction SilentlyContinue)

    $copied = 0
    $skipped = 0
    $bytes = [int64]0

    foreach ($f in $files) {
        if ($exclude -and $f.FullName.StartsWith($exclude, [StringComparison]::OrdinalIgnoreCase)) { continue }
        $rel = $f.FullName.Substring($base.Length)
        $target = Join-Path $DestDir $rel
        try {
            $targetDir = Split-Path -Parent $target
            if (-not (Test-Path -LiteralPath $targetDir)) {
                New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
            }
            Copy-Item -LiteralPath $f.FullName -Destination $target -Force -ErrorAction Stop
            $copied++
            $bytes += $f.Length
        } catch {
            $skipped++
        }
    }

    return [pscustomobject]@{ Copied = $copied; Skipped = $skipped; SourceBytes = $bytes }
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

    # --- Storage (kamera suratlari + nakladnoy PDF) zaxirasi ---
    $storageMuvaffaqiyat = $null
    if (-not ($BackupStorage -and (-not $SkipStorage))) {
        $sabab = if ($SkipStorage) { "-SkipStorage berilgan" } else { "backup_config.ps1'da BackupStorage = `$false" }
        Write-Log "Storage zaxirasi o'tkazib yuborildi ($sabab)."
    } else {
        try {
            $storageDir = Get-StorageDir
            if (-not (Test-Path -LiteralPath $storageDir)) {
                Write-Log "Storage papkasi topilmadi ($storageDir) - zaxira o'tkazib yuborildi (hali surat/PDF bo'lmasligi mumkin)." "WARN"
                $storageMuvaffaqiyat = $true
            } else {
                $storageBackupName = "storage_${timestamp}"
                $storageBackupLocal = Join-Path $BackupLocalDir $storageBackupName
                Write-Log "Storage papkasi: $storageDir"
                Write-Log "Storage nusxasi: $storageBackupLocal"

                if (Test-Path -LiteralPath $storageBackupLocal) {
                    Remove-Item -LiteralPath $storageBackupLocal -Recurse -Force
                }
                New-Item -ItemType Directory -Force -Path $storageBackupLocal | Out-Null

                $r = Copy-StorageFolder -SourceDir $storageDir -DestDir $storageBackupLocal -ExcludePrefix $BackupLocalDir

                if ($r.Copied -eq 0 -and $r.Skipped -eq 0) {
                    Write-Log "Storage papkasi bo'sh - nusxa saqlanmadi." "WARN"
                    Remove-Item -LiteralPath $storageBackupLocal -Recurse -Force -ErrorAction SilentlyContinue
                    $storageMuvaffaqiyat = $true
                } elseif ($r.Copied -eq 0) {
                    throw "Storage nusxasiga birorta ham fayl ko'chirilmadi ($($r.Skipped) ta fayl o'qib bo'lmadi)."
                } else {
                    $srcMb = [math]::Round($r.SourceBytes / 1MB, 1)
                    $srcGb = [math]::Round($r.SourceBytes / 1GB, 2)
                    Write-Log "Storage nusxasi tayyor: $storageBackupLocal ($($r.Copied) fayl; ~$srcMb MB)"
                    if ($r.Skipped -gt 0) {
                        Write-Log "Storage: $($r.Skipped) ta fayl o'qib bo'lmadi (qulflangan bo'lishi mumkin) - nusxaga kirmadi." "WARN"
                    }
                    if ($srcGb -ge $StorageWarnGB) {
                        Write-Log ("OGOHLANTIRISH: storage hajmi ~{0} GB. Har kuni to'liq nusxa olish disk joyini tez to'ldirishi mumkin - docs\BACKUP.md 'Katta storage papkasi' bo'limiga qarang." -f $srcGb) "WARN"
                    }

                    if ($BackupRemoteDir) {
                        try {
                            if (-not (Test-Path $BackupRemoteDir)) {
                                New-Item -ItemType Directory -Force -Path $BackupRemoteDir | Out-Null
                            }
                            $storageRemote = Join-Path $BackupRemoteDir $storageBackupName
                            if (Test-Path -LiteralPath $storageRemote) {
                                Remove-Item -LiteralPath $storageRemote -Recurse -Force
                            }
                            Copy-Item -LiteralPath $storageBackupLocal -Destination $storageRemote -Recurse -Force
                            Write-Log "Storage nusxasi tashqi joyga ko'chirildi: $storageRemote"
                        } catch {
                            Write-Log "Storage nusxasini tashqi joyga ko'chirishda xato: $($_.Exception.Message)" "WARN"
                        }
                    }
                    $storageMuvaffaqiyat = $true
                }
            }
        } catch {
            $storageMuvaffaqiyat = $false
            Write-Log "Storage zaxirasida XATO: $($_.Exception.Message)" "WARN"
            Write-Log "Baza backup'i muvaffaqiyatli - skript davom etadi, storage keyingi safar qayta uriniladi." "WARN"
        }
    }

    # --- Eski fayllarni tozalash: .dump fayllar VA storage nusxa papkalari ---
    Remove-OldBackups -Dir $BackupLocalDir -Days $RetentionDays
    Remove-OldBackups -Dir $BackupLocalDir -Days $RetentionDays -Filter "storage_*" -Folder
    if ($BackupRemoteDir -and (Test-Path $BackupRemoteDir)) {
        Remove-OldBackups -Dir $BackupRemoteDir -Days $RetentionDays
        Remove-OldBackups -Dir $BackupRemoteDir -Days $RetentionDays -Filter "storage_*" -Folder
    }

    if ($storageMuvaffaqiyat -eq $false) {
        Write-Log "Backup yakunlandi - LEKIN storage zaxirasi MUVAFFAQIYATSIZ (yuqoridagi WARN). Baza .dump'i saqlandi." "WARN"
    } else {
        Write-Log "Backup muvaffaqiyatli yakunlandi."
    }
    exit 0
} catch {
    Write-Log "XATO: $($_.Exception.Message)" "ERROR"
    exit 1
}

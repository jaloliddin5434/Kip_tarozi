<#
    Kip Tarozi - backup skriptlari uchun umumiy funksiyalar.

    Ikkala skript ham shu fayldan dot-source qilib foydalanadi (kod
    takrorlanishining oldini olish uchun):
      - scripts\backup_yarat.ps1       (kechqurungi, 03:00, TO'LIQ backup:
                                         baza dump + storage xom nusxa +
                                         tushunarli tuzilma, tarixiy nusxalar
                                         bilan)
      - scripts\tezkor_yangilash.ps1   (kuniga 3 marta, 08:10/16:10/00:10,
                                         FAQAT tushunarli tuzilma - baza
                                         dumpsiz, bitta ustidan yoziladigan
                                         mahalliy/tashqi papka bilan)

    Foydalanish:
        . (Join-Path $ScriptDir "backup_common.ps1")
#>

function Write-BackupLog {
    <#
        Bitta qatorni ham konsolga, ham $LogFile'ga yozadi. Har ikkala
        skript o'z alohida log faylidan foydalanadi (backup.log /
        tezkor_yangilash.log) - shuning uchun $LogFile HAR SAFAR aniq
        beriladi (script-scope o'zgaruvchiga yashirin tayanmaydi).
    #>
    param(
        [Parameter(Mandatory)][string]$LogFile,
        [Parameter(Mandatory)][string]$Message,
        [string]$Level = "INFO"
    )
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

function Invoke-BackupTuzilma {
    <#
        backend\scripts\backup_tuzilma.py'ni chaqiradi - u bazadan REAL
        O'QIB, $Dest ichida "KIP-Tarozi Rasm", "KIP-Tarozi Excel" va
        "KIP-Tarozi Nakladnoy" papkalarini yaratadi/yangilaydi (tushunarli
        tuzilma).

        MUHIM: bu skript bazadan FAQAT O'QIYDI, asl storage\ papkasiga
        tegmaydi. Xato bo'lsa - throw qiladi (chaqiruvchi o'zi hal qiladi -
        backup_yarat.ps1'da WARN bilan davom etiladi, tezkor_yangilash.ps1'da
        bu qadam skriptning yagona vazifasi bo'lgani uchun xato fatal).
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Dest,
        [Parameter(Mandatory)][string]$LogFile
    )

    $py = Join-Path $Root "backend\.venv\Scripts\python.exe"
    if (-not (Test-Path $py)) { $py = "python" }
    $backendDir = Join-Path $Root "backend"

    Push-Location $backendDir
    # Native stderr'ni $ErrorActionPreference='Stop' bilan qo'shganda PS 5.1
    # "NativeCommandError" tashlashi mumkin - shu blokda vaqtincha yumshatamiz.
    $eskiEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $chiqish = & $py -m scripts.backup_tuzilma --dest $Dest 2>&1
        $exit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $eskiEAP
        Pop-Location
    }
    foreach ($qator in $chiqish) { Write-BackupLog -LogFile $LogFile -Message "  [tuzilma] $qator" }
    if ($exit -ne 0) { throw "backup_tuzilma.py exit code $exit" }
}

function Copy-ToRemoteFolder {
    <#
        $LocalDir (papka) ni $RemoteDir\$Name ostiga ko'chiradi - avval
        o'sha nomdagi eski nusxa (bo'lsa) o'chiriladi. $RemoteDir bo'sh
        bo'lsa yoki nusxalashda xato chiqsa (masalan tashqi kompyuter/tarmoq
        papkasi ayni damda yo'q) - THROW QILMAYDI, faqat WARN yozib $false
        qaytaradi - chaqiruvchi skript shu tufayli to'xtamasligi kerak
        (mahalliy nusxa baribir saqlangan bo'ladi, keyingi ishga tushishda
        qayta uriniladi).
    #>
    param(
        [Parameter(Mandatory)][string]$LocalDir,
        [string]$RemoteDir,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$LogFile
    )

    if (-not $RemoteDir) {
        Write-BackupLog -LogFile $LogFile -Message "BackupRemoteDir sozlanmagan - faqat mahalliy nusxa saqlandi (docs\BACKUP.md'ga qarang)." -Level "WARN"
        return $false
    }

    try {
        if (-not (Test-Path $RemoteDir)) {
            New-Item -ItemType Directory -Force -Path $RemoteDir | Out-Null
        }
        $remotePath = Join-Path $RemoteDir $Name
        if (Test-Path -LiteralPath $remotePath) {
            Remove-Item -LiteralPath $remotePath -Recurse -Force
        }
        Copy-Item -LiteralPath $LocalDir -Destination $remotePath -Recurse -Force
        Write-BackupLog -LogFile $LogFile -Message "Tashqi joyga ko'chirildi: $remotePath"
        return $true
    } catch {
        Write-BackupLog -LogFile $LogFile -Message "Tashqi joyga ko'chirishda xato: $($_.Exception.Message)" -Level "WARN"
        return $false
    }
}

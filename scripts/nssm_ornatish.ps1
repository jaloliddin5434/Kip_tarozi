<#
    Kip Tarozi - NSSM orqali Windows xizmatlarini o'rnatish.

    Backend (uvicorn) va Stansiya Agentni Windows xizmati sifatida
    o'rnatadi, avtomatik qayta ishga tushirish (watchdog) sozlangan holda:
      - KipTaroziBackend  -> app.main:app
      - KipTaroziAgent    -> app.services.rs232.station_agent:app

    MUHIM: Bu xizmat nomlari loyihadagi boshqa (Hazorasp*, CloudflaredTunnel)
    xizmatlardan ATAYLAB farqlanadi va skript pastda shu nomlarni
    o'zgartirishga yo'l qo'ymaydi (bloklangan ro'yxatga qarang).

    Talablar:
      - NSSM kompyuterda o'rnatilgan (PATH'da yoki -NssmPath bilan ko'rsatilgan)
      - Administrator huquqi bilan ishga tushirilgan PowerShell
      - backend\.venv allaqachon yaratilgan (pip install -r requirements.txt)

    Ishga tushirish (Administrator sifatida):
      powershell -ExecutionPolicy Bypass -File scripts\nssm_ornatish.ps1

    To'liq yo'riqnoma: docs\NSSM_ORNATISH.md
#>

param(
    [string]$ProjectRoot = "C:\Kip_tarozi",
    [string]$NssmPath = "nssm.exe",
    [int]$BackendPort = 8000,
    [int]$AgentPort = 8100,
    [switch]$XizmatlarniIshgaTushirish
)

$ErrorActionPreference = "Stop"

# --- Xavfsizlik: shu skript hech qachon boshqa (mavjud) xizmat nomlarini
# o'rnatmasligi/o'zgartirmasligi kerak. Ro'yxat ataylab hardcode qilingan -
# ishga tushirishda ham, keyinchalik kimdir parametr xato bergan taqdirda ham
# himoya bo'lsin uchun. ---
$TaqiqlanganXizmatNomlari = @("HazoraspBackend", "HazoraspFrontend", "CloudflaredTunnel")

$BackendXizmatNomi = "KipTaroziBackend"
$AgentXizmatNomi = "KipTaroziAgent"

foreach ($nom in @($BackendXizmatNomi, $AgentXizmatNomi)) {
    if ($TaqiqlanganXizmatNomlari -contains $nom) {
        throw "Xavfsizlik xatosi: '$nom' mavjud tizim xizmati nomi bilan to'qnashadi. Skript to'xtatildi."
    }
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    throw "Bu skript Administrator huquqi bilan ishga tushirilishi kerak (Windows xizmat o'rnatish uchun)."
}

$nssmKomandasi = Get-Command $NssmPath -ErrorAction SilentlyContinue
if (-not $nssmKomandasi) {
    throw "nssm.exe topilmadi ('$NssmPath'). Avval NSSM'ni o'rnating - docs\NSSM_ORNATISH.md'ga qarang."
}
$Nssm = $nssmKomandasi.Source

$PythonExe = Join-Path $ProjectRoot "backend\.venv\Scripts\python.exe"
if (-not (Test-Path $PythonExe)) {
    throw "python.exe topilmadi: $PythonExe - avval backend\.venv yarating (pip install -r requirements.txt)."
}

$BackendDir = Join-Path $ProjectRoot "backend"
if (-not (Test-Path $BackendDir)) {
    throw "Backend papkasi topilmadi: $BackendDir"
}

$LogDir = Join-Path $ProjectRoot "backups\nssm-logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Install-KipTaroziXizmat {
    param(
        [string]$Nomi,
        [string]$KorsatishNomi,
        [string]$Tavsif,
        [string]$Argumentlar,
        [string]$IshDirektoriyasi,
        [string]$StdoutLog,
        [string]$StderrLog
    )

    if ($TaqiqlanganXizmatNomlari -contains $Nomi) {
        throw "Xavfsizlik xatosi: '$Nomi' taqiqlangan xizmat nomi."
    }

    Write-Host "O'rnatilmoqda: $Nomi ..." -ForegroundColor Cyan

    & $Nssm install $Nomi $PythonExe $Argumentlar
    if ($LASTEXITCODE -ne 0) {
        throw "'$Nomi' o'rnatilmadi (nssm install exit code $LASTEXITCODE). Xizmat allaqachon mavjud bo'lishi mumkin - avval scripts\nssm_ochirish.ps1 bilan o'chiring."
    }

    & $Nssm set $Nomi AppDirectory $IshDirektoriyasi
    & $Nssm set $Nomi DisplayName $KorsatishNomi
    & $Nssm set $Nomi Description $Tavsif
    & $Nssm set $Nomi Start SERVICE_AUTO_START

    # Watchdog: xizmat qanday sabab bilan to'xtamasin (xato, ishdan chiqish),
    # NSSM uni avtomatik qayta ishga tushiradi.
    & $Nssm set $Nomi AppExit Default Restart
    & $Nssm set $Nomi AppRestartDelay 3000
    & $Nssm set $Nomi AppThrottle 1500

    # Log fayllar + kunlik/hajm bo'yicha rotatsiya (disk to'lib qolmasligi uchun).
    & $Nssm set $Nomi AppStdout $StdoutLog
    & $Nssm set $Nomi AppStderr $StderrLog
    & $Nssm set $Nomi AppRotateFiles 1
    & $Nssm set $Nomi AppRotateOnline 1
    & $Nssm set $Nomi AppRotateBytes 10485760

    Write-Host "O'rnatildi: $Nomi" -ForegroundColor Green
}

Install-KipTaroziXizmat `
    -Nomi $BackendXizmatNomi `
    -KorsatishNomi "Kip Tarozi - Backend" `
    -Tavsif "Kip Tarozi FastAPI backend (uvicorn, port $BackendPort)" `
    -Argumentlar "-m uvicorn app.main:app --host 0.0.0.0 --port $BackendPort" `
    -IshDirektoriyasi $BackendDir `
    -StdoutLog (Join-Path $LogDir "backend.out.log") `
    -StderrLog (Join-Path $LogDir "backend.err.log")

Install-KipTaroziXizmat `
    -Nomi $AgentXizmatNomi `
    -KorsatishNomi "Kip Tarozi - Stansiya Agenti" `
    -Tavsif "Kip Tarozi RS232 stansiya agenti (uvicorn, port $AgentPort)" `
    -Argumentlar "-m uvicorn app.services.rs232.station_agent:app --host 0.0.0.0 --port $AgentPort" `
    -IshDirektoriyasi $BackendDir `
    -StdoutLog (Join-Path $LogDir "agent.out.log") `
    -StderrLog (Join-Path $LogDir "agent.err.log")

if ($XizmatlarniIshgaTushirish) {
    Write-Host "Xizmatlar ishga tushirilmoqda ..." -ForegroundColor Cyan
    & $Nssm start $BackendXizmatNomi
    & $Nssm start $AgentXizmatNomi
} else {
    Write-Host ""
    Write-Host "Xizmatlar o'rnatildi, lekin hali ishga tushirilmadi." -ForegroundColor Yellow
    Write-Host "Ishga tushirish uchun: nssm start $BackendXizmatNomi  va  nssm start $AgentXizmatNomi"
    Write-Host "(yoki shu skriptni -XizmatlarniIshgaTushirish bilan qayta ishga tushiring)"
}

Write-Host ""
Write-Host "Tayyor. Xizmat nomlari: $BackendXizmatNomi, $AgentXizmatNomi" -ForegroundColor Green

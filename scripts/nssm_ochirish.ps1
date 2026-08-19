<#
    Kip Tarozi - NSSM orqali o'rnatilgan Windows xizmatlarini o'chirish.

    FAQAT shu ikki xizmatga tegadi:
      - KipTaroziBackend
      - KipTaroziAgent

    Loyihadagi boshqa xizmatlarga (Hazorasp*, CloudflaredTunnel va h.k.)
    HECH QACHON tegilmaydi - skript ularning nomini bilmaydi ham, bilishni
    ham talab qilmaydi.

    Ishga tushirish (Administrator sifatida):
      powershell -ExecutionPolicy Bypass -File scripts\nssm_ochirish.ps1

    To'liq yo'riqnoma: docs\NSSM_ORNATISH.md
#>

param(
    [string]$NssmPath = "nssm.exe",
    [switch]$Majburiy
)

$ErrorActionPreference = "Stop"

$TaqiqlanganXizmatNomlari = @("HazoraspBackend", "HazoraspFrontend", "CloudflaredTunnel")
$OchiriladiganXizmatlar = @("KipTaroziBackend", "KipTaroziAgent")

foreach ($nom in $OchiriladiganXizmatlar) {
    if ($TaqiqlanganXizmatNomlari -contains $nom) {
        throw "Xavfsizlik xatosi: '$nom' taqiqlangan xizmat nomi - skript to'xtatildi."
    }
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    throw "Bu skript Administrator huquqi bilan ishga tushirilishi kerak (Windows xizmat o'chirish uchun)."
}

$nssmKomandasi = Get-Command $NssmPath -ErrorAction SilentlyContinue
if (-not $nssmKomandasi) {
    throw "nssm.exe topilmadi ('$NssmPath'). docs\NSSM_ORNATISH.md'ga qarang."
}
$Nssm = $nssmKomandasi.Source

Write-Host "O'chiriladigan xizmatlar (FAQAT shular):" -ForegroundColor Yellow
foreach ($nom in $OchiriladiganXizmatlar) { Write-Host "  - $nom" }
Write-Host ""

if (-not $Majburiy) {
    $javob = Read-Host "Davom etish uchun aniq 'HA' deb yozing"
    if ($javob -cne "HA") {
        Write-Host "Bekor qilindi - hech narsa o'chirilmadi." -ForegroundColor Cyan
        exit 1
    }
}

foreach ($nom in $OchiriladiganXizmatlar) {
    Write-Host "To'xtatilmoqda va o'chirilmoqda: $nom ..." -ForegroundColor Cyan
    & $Nssm stop $nom
    & $Nssm remove $nom confirm
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Ogohlantirish: '$nom' o'chirilmadi (balki allaqachon mavjud emas)." -ForegroundColor Yellow
    } else {
        Write-Host "O'chirildi: $nom" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Tayyor." -ForegroundColor Green

# Build (bila perlu) lalu jalankan gateway Go mpos-backend di 127.0.0.1:8787.
# Output build ditaruh di %LOCALAPPDATA% karena Controlled Folder Access
# memblokir toolchain menulis ke folder proyek OneDrive.
#
# Pakai:  powershell -ExecutionPolicy Bypass -File tools\run-backend.ps1

$ErrorActionPreference = 'Stop'

$backendSrc = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'backend'
$exe = Join-Path $env:LOCALAPPDATA 'ipos-build\backend\mpos-backend.exe'

Write-Host "== mpos-backend =="
Write-Host "Sumber : $backendSrc"

Push-Location $backendSrc
try {
    go build -o $exe .
    if ($LASTEXITCODE -ne 0) { throw "go build gagal" }
} finally {
    Pop-Location
}

Write-Host "Binary : $exe"
Write-Host "Listen : http://127.0.0.1:8787  (upstream: https://tatreport.com)"
Write-Host "Arahkan aplikasi MPos: Pengaturan -> Ubah URL server -> http://localhost:8787"
Write-Host "Hentikan dengan Ctrl+C.`n"

& $exe

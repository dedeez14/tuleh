# Build (bila perlu) lalu jalankan gateway Go mpos-backend di 127.0.0.1:8787.
# Output build ditaruh di %LOCALAPPDATA% karena Controlled Folder Access
# memblokir toolchain menulis ke folder proyek OneDrive.
#
# Pakai:  powershell -ExecutionPolicy Bypass -File tools\run-backend.ps1 -Upstream https://domain-server-anda
#
# Tidak ada server bawaan tertanam: -Upstream (atau env MPOS_UPSTREAM) wajib diisi.
# Versi gateway = versi aplikasi di frontend/package.json (ditanam lewat -ldflags), sama
# seperti build CI — aplikasi tidak memakai ulang gateway dengan versi berbeda.

param(
    [string]$Upstream = $env:MPOS_UPSTREAM
)

$ErrorActionPreference = 'Stop'

if (-not $Upstream) { throw "Isi -Upstream https://domain-server-anda (atau env MPOS_UPSTREAM)." }

$frontendDir = Split-Path -Parent $PSScriptRoot
$backendSrc = Join-Path (Split-Path -Parent $frontendDir) 'backend'
$exe = Join-Path $env:LOCALAPPDATA 'ipos-build\backend\mpos-backend.exe'
$versi = (Get-Content (Join-Path $frontendDir 'package.json') -Raw | ConvertFrom-Json).version

Write-Host "== mpos-backend $versi =="
Write-Host "Sumber : $backendSrc"

Push-Location $backendSrc
try {
    go build -ldflags "-X main.appVersion=$versi" -o $exe .
    if ($LASTEXITCODE -ne 0) { throw "go build gagal" }
} finally {
    Pop-Location
}

Write-Host "Binary : $exe"
Write-Host "Listen : http://127.0.0.1:8787  (upstream: $Upstream)"
Write-Host "Aplikasi memakai gateway ini otomatis bila upstream & versinya sama (Pengaturan -> Aplikasi -> Gateway lokal)."
Write-Host "Hentikan dengan Ctrl+C.`n"

$env:MPOS_UPSTREAM = $Upstream
& $exe

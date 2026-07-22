# Build installer Windows (.exe) untuk MPos.
#
# Kenapa lewat mirror: Controlled Folder Access memblokir node/npm menulis ke
# OneDrive\Documents, jadi sumber di-mirror dulu ke %LOCALAPPDATA%\ipos-build\app
# lalu npm install + electron-builder dijalankan di sana.
#
# Ikon: taruh PNG persegi >= 256px di salah satu dari (urutan prioritas):
#   1. <frontend>\build\icon.png            (di dalam proyek, bila CFA sudah diizinkan)
#   2. %LOCALAPPDATA%\ipos-build\icon.png   (di luar folder terproteksi)
# electron-builder otomatis mengubahnya menjadi .ico multi-ukuran.
#
# Pakai:  powershell -ExecutionPolicy Bypass -File tools\build-win.ps1

$ErrorActionPreference = 'Stop'

$srcDir = Split-Path -Parent $PSScriptRoot          # <frontend>
$workRoot = Join-Path $env:LOCALAPPDATA 'ipos-build'
$appDir = Join-Path $workRoot 'app'

Write-Host "== Tuleh build =="
Write-Host "Sumber : $srcDir"
Write-Host "Kerja  : $appDir"

New-Item -ItemType Directory -Force -Path $appDir | Out-Null

# 1. Mirror sumber (tanpa node_modules/dist agar bersih & cepat)
robocopy $srcDir $appDir /MIR /NFL /NDL /NJH /NJS /XD node_modules dist .git | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy gagal (kode $LASTEXITCODE)" }

# 2. Siapkan ikon
$iconProject = Join-Path $srcDir 'build\icon.png'
$iconShared = Join-Path $workRoot 'icon.png'
$iconTarget = Join-Path $appDir 'build\icon.png'
New-Item -ItemType Directory -Force -Path (Join-Path $appDir 'build') | Out-Null
if (Test-Path $iconProject) {
    Copy-Item $iconProject $iconTarget -Force
    Write-Host "Ikon  : dari proyek (build\icon.png)"
} elseif (Test-Path $iconShared) {
    Copy-Item $iconShared $iconTarget -Force
    Write-Host "Ikon  : dari $iconShared"
} else {
    Write-Warning "icon.png tidak ditemukan - installer memakai ikon default Electron."
}

# 2b. Bundel gateway Go (extraResources) — dilewati bila Go tidak terpasang
$goExe = Get-Command go -ErrorAction SilentlyContinue
if ($goExe) {
    $backendSrc = Join-Path (Split-Path -Parent $srcDir) 'backend'
    $backendOut = Join-Path $appDir 'build\backend\mpos-backend.exe'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backendOut) | Out-Null
    Push-Location $backendSrc
    try {
        go build -o $backendOut .
        if ($LASTEXITCODE -ne 0) { throw "go build gateway gagal" }
        Write-Host "Gateway: dibundel ($backendOut)"
    } finally {
        Pop-Location
    }
} else {
    # Folder tetap dibuat (kosong) agar konfigurasi extraResources tidak error
    New-Item -ItemType Directory -Force -Path (Join-Path $appDir 'build\backend') | Out-Null
    Write-Warning "Go tidak ditemukan - installer dibangun TANPA gateway lokal."
}

# 3. Bersihkan artefak installer lama (bisa terkunci oleh scan Defender →
#    makensis gagal "Can't open output file")
$staleDist = Join-Path $appDir 'dist'
if (Test-Path $staleDist) {
    Get-ChildItem $staleDist -Filter '*.exe' -ErrorAction SilentlyContinue |
        ForEach-Object { try { Remove-Item $_.FullName -Force -Confirm:$false } catch {} }
    Get-ChildItem $staleDist -Filter '*.blockmap' -ErrorAction SilentlyContinue |
        ForEach-Object { try { Remove-Item $_.FullName -Force -Confirm:$false } catch {} }
}

# 4. Instal dependensi + build (tanpa code signing)
Push-Location $appDir
try {
    if (Test-Path Env:\ELECTRON_RUN_AS_NODE) { Remove-Item Env:\ELECTRON_RUN_AS_NODE }
    $env:CSC_IDENTITY_AUTO_DISCOVERY = 'false'

    Write-Host "`n-- npm install --"
    npm install --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) { throw "npm install gagal" }

    Write-Host "`n-- electron-builder --"
    npx electron-builder --win
    if ($LASTEXITCODE -ne 0) { throw "electron-builder gagal" }
} finally {
    Pop-Location
}

# 5. Tunjukkan hasil + salin installer ke Downloads bila bisa
$distDir = Join-Path $appDir 'dist'
$installer = Get-ChildItem $distDir -Filter 'Tuleh-Setup-*.exe' | Select-Object -First 1
Write-Host "`n== Selesai =="
Write-Host "Installer : $($installer.FullName)"
Write-Host "Portable  : $distDir\win-unpacked\Tuleh.exe"

try {
    $target = Join-Path "$env:USERPROFILE\Downloads" $installer.Name
    Copy-Item $installer.FullName $target -Force
    Write-Host "Disalin ke: $target"
} catch {
    Write-Warning "Tidak bisa menyalin ke Downloads: $($_.Exception.Message)"
}

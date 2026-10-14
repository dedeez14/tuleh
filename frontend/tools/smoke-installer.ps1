$ErrorActionPreference = 'Stop'
$smokeRoot = Join-Path $env:RUNNER_TEMP 'tuleh-install-smoke'
$installDir = Join-Path $smokeRoot 'app'
$profileDir = Join-Path $smokeRoot 'profile'
$reportPath = Join-Path $smokeRoot 'report.json'
New-Item -ItemType Directory -Force $profileDir | Out-Null
# Profil baru tanpa token/antrean pengguna dan tanpa koneksi ke server produksi.
@{ baseUrl = 'https://tuleh-smoke.invalid' } | ConvertTo-Json | Set-Content (Join-Path $profileDir 'settings.json') -Encoding utf8NoBOM
$version = (Get-Content (Join-Path $PSScriptRoot '../package.json') -Raw | ConvertFrom-Json).version
$installer = (Resolve-Path (Join-Path $PSScriptRoot "../dist/Tuleh-Setup-$version.exe")).Path
$setup = Start-Process -FilePath $installer -ArgumentList @('/S', "/D=$installDir") -WindowStyle Hidden -PassThru
if (-not $setup.WaitForExit(120000)) { throw 'Instalasi melewati batas waktu.' }
if ($setup.ExitCode -ne 0) { throw "Installer gagal: $($setup.ExitCode)" }
$exe = Join-Path $installDir 'Tuleh.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw 'Executable tidak ditemukan setelah instalasi.' }
$env:IPOS_SMOKE = '1'
$env:IPOS_SMOKE_DEMO = '1'
$env:IPOS_SMOKE_SCREEN = 'pos'
$env:IPOS_SMOKE_DELAY = '15000'
$env:IPOS_SMOKE_USER_DATA = $profileDir
$env:IPOS_SMOKE_OUT = $reportPath
$env:IPOS_SMOKE_SHOT = Join-Path $smokeRoot 'report.png'
$appProcess = Start-Process -FilePath $exe -WindowStyle Hidden -PassThru
if (-not $appProcess.WaitForExit(90000)) { throw 'Aplikasi tidak menyelesaikan pengujian startup.' }
if ($appProcess.ExitCode -ne 0) { throw "Aplikasi gagal: $($appProcess.ExitCode)" }
if (-not (Test-Path -LiteralPath $reportPath)) { throw 'Laporan startup tidak dihasilkan.' }
node (Join-Path $PSScriptRoot 'verify-smoke.cjs') $reportPath
if ($LASTEXITCODE -ne 0) { throw 'Verifikasi aplikasi hasil instalasi gagal.' }

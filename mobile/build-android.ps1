# Rakit www/ dari frontend/ lalu build APK Tuléh Android (Capacitor).
# Jalankan dari folder mobile/:  powershell -ExecutionPolicy Bypass -File build-android.ps1
$ErrorActionPreference = 'Stop'
$mobile   = $PSScriptRoot
$repo     = Split-Path $mobile -Parent
$renderer = Join-Path $repo 'frontend\src\renderer'
$qrlib    = Join-Path $repo 'frontend\src\main\lib\qrcode-generator.js'
$www      = Join-Path $mobile 'www'

Write-Host '1/4 Dependencies…'
if (-not (Test-Path (Join-Path $mobile 'node_modules'))) {
  Push-Location $mobile; npm install; Pop-Location
}

Write-Host '2/4 Merakit www/ (renderer + qrcode + overlay mobile)…'
if (Test-Path $www) { Remove-Item $www -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $www 'js\lib') -Force | Out-Null
Copy-Item (Join-Path $renderer '*') $www -Recurse -Force
Copy-Item $qrlib (Join-Path $www 'js\lib\qrcode-generator.js') -Force
Copy-Item (Join-Path $mobile 'www-src\*') $www -Recurse -Force   # overlay: index.html + mobile-bridge.js

Write-Host '3/4 Capacitor sync…'
Push-Location $mobile
if (Test-Path (Join-Path $mobile 'android')) { npx cap sync android } else { npx cap add android }
Pop-Location

Write-Host '4/4 Gradle assembleDebug…'
$env:JAVA_HOME    = 'C:\Program Files\Android\Android Studio\jbr'
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
Push-Location (Join-Path $mobile 'android')
& .\gradlew.bat assembleDebug --console=plain
Pop-Location

Write-Host ''
Write-Host 'APK: mobile\android\app\build\outputs\apk\debug\app-debug.apk'

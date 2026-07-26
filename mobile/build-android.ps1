# Rakit www/ dari frontend/ + ikon + build APK Tuléh Android (Capacitor).
# Jalankan dari folder mobile/:  powershell -ExecutionPolicy Bypass -File build-android.ps1
$ErrorActionPreference = 'Stop'
$mobile   = $PSScriptRoot
$repo     = Split-Path $mobile -Parent
$renderer = Join-Path $repo 'frontend\src\renderer'
$srcMain  = Join-Path $repo 'frontend\src\main'
$www      = Join-Path $mobile 'www'

Write-Host '1/5 Dependencies…'
if (-not (Test-Path (Join-Path $mobile 'node_modules'))) { Push-Location $mobile; npm install; Pop-Location }

Write-Host '2/5 Merakit www/ (renderer + qrcode + demo + overlay mobile)…'
if (Test-Path $www) { Remove-Item $www -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $www 'js\lib') -Force | Out-Null
Copy-Item (Join-Path $renderer '*') $www -Recurse -Force
Copy-Item (Join-Path $srcMain 'lib\qrcode-generator.js') (Join-Path $www 'js\lib\qrcode-generator.js') -Force

# Bungkus demo.js/demo-data.js (CommonJS) agar jalan di browser (window.__cjs.define)
function Wrap-Cjs([string]$name, [string]$src, [string]$dest) {
  $head = "window.__cjs.define('$name', function (module, exports, require) {`r`n"
  $body = Get-Content $src -Raw
  [IO.File]::WriteAllText($dest, $head + $body + "`r`n});", (New-Object Text.UTF8Encoding($false)))
}
Wrap-Cjs 'demo-data' (Join-Path $srcMain 'demo-data.js') (Join-Path $www 'js\demo-data.js')
Wrap-Cjs 'demo'      (Join-Path $srcMain 'demo.js')      (Join-Path $www 'js\demo.js')
Copy-Item (Join-Path $mobile 'www-src\*') $www -Recurse -Force   # overlay: index.html + mobile-bridge.js

Write-Host '3/5 Capacitor sync + ikon/splash…'
Push-Location $mobile
if (Test-Path (Join-Path $mobile 'android')) { npx cap sync android } else { npx cap add android }
# assets/ sudah ada di repo; regenerasi dari logo bila perlu: python gen-icons.py
npx capacitor-assets generate --android
Pop-Location

Write-Host '4/5 Gradle assembleDebug…'
$env:JAVA_HOME    = 'C:\Program Files\Android\Android Studio\jbr'
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
Push-Location (Join-Path $mobile 'android')
& .\gradlew.bat assembleDebug --console=plain
Pop-Location

Write-Host '5/5 Selesai.'
Write-Host 'APK: mobile\android\app\build\outputs\apk\debug\app-debug.apk'

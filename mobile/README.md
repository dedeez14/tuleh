# Tuléh Android (Capacitor)

Versi **Android** dari Tuléh — membungkus **UI web yang sama** (`../frontend/src/renderer`)
dengan [Capacitor](https://capacitorjs.com/) di dalam WebView native, lalu
menyediakan jembatan `window.iposAPI` yang memanggil **MOVERA POS API langsung**
(pengganti proses main Electron di desktop).

## Arsitektur

```
Desktop (Electron):  renderer ──IPC──▶ main (ipc.js) ──▶ gateway Go ──▶ MOVERA
Android (Capacitor): renderer ──▶ www-src/js/mobile-bridge.js ──(CapacitorHttp, native)──▶ MOVERA
```

- `www-src/js/mobile-bridge.js` — mengimplementasikan **seluruh permukaan
  `window.iposAPI`** (auth, produk, transaksi, sesi, orders, bills, langganan,
  cs, dll.) dengan memanggil `https://<server>/api/pos/v1` langsung. Token &
  pengaturan disimpan via **Capacitor Preferences**. QR (struk/meja) dibuat di
  perangkat dengan `qrcode-generator`. `?toko_id` disisipkan otomatis (multi-toko).
- `www-src/index.html` — index versi mobile (tanpa CSP ketat desktop yang akan
  memblokir jembatan Capacitor; data tetap di-escape di renderer).
- `CapacitorHttp: { enabled: true }` (capacitor.config.json) mem-patch `fetch`
  → HTTP native, sehingga **bebas CORS**.

## Fitur yang ditunda (khusus desktop, tidak dibawa ke v1 Android)

- Server LAN pelacakan pelanggan (`/t`, `/o`, `/antrian`) & QR-meja self-order —
  butuh hosting server; pelacakan via QR struk tetap jalan karena menunjuk
  `/api/pos/v1/public/track/{token}` di domain server.
- Cloudflare tunnel (tidak relevan di HP).
- Cetak thermal 80mm Electron → di Android memakai dialog cetak sistem
  (`window.print` → PDF/printer); printer Bluetooth = v2.
- Mode Demo (belum di-port ke jembatan mobile).

## Prasyarat

- Node.js ≥ 18
- Android SDK (platform **android-35** + build-tools **35.0.0**) — mis. via Android Studio
- JDK 17/21 — mis. JBR bawaan Android Studio (`…\Android Studio\jbr`)

## Build APK (debug)

```powershell
# dari folder mobile/
powershell -ExecutionPolicy Bypass -File build-android.ps1
```

Skrip ini: `npm install` → merakit `www/` (salin `../frontend/src/renderer` +
`qrcode-generator.js` + overlay `www-src/`) → `npx cap sync android` →
`gradlew assembleDebug`. Hasil: `android/app/build/outputs/apk/debug/app-debug.apk`.

Manual:
```powershell
npm install
# rakit www/ (lihat build-android.ps1), lalu:
npx cap add android      # sekali; berikutnya: npx cap sync android
cd android
$env:JAVA_HOME="C:\Program Files\Android\Android Studio\jbr"
.\gradlew.bat assembleDebug
```

## Catatan

- APK saat ini **debug-signed** (untuk uji & sideload). Untuk distribusi Play
  Store / produksi: buat keystore + konfigurasi `signingConfig` release lalu
  `gradlew assembleRelease`.
- `www/`, `android/`, dan `node_modules/` **derivatif** — tidak di-commit
  (di-.gitignore); dibangun ulang oleh skrip.

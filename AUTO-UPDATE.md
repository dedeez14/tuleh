# Auto-Update Tuléh (Desktop .exe + Android .apk)

Sistem pembaruan aplikasi dalam-app: cek versi ke server, layar update wajib/opsional,
lalu unduh + pasang otomatis. Semua teks bahasa Indonesia; **fail-open** (kegagalan cek
tak pernah memblokir aplikasi) — penegakan keras dilakukan lewat HTTP **426**.

## Alur singkat

1. Setiap request API mengirim header `X-Tuleh-Version: <versi app>` (satu sumber:
   `app.getVersion()` desktop / `APP_VERSION` Android — tidak di-hardcode).
2. Server boleh membalas **426** dari endpoint mana pun bila versi di bawah minimum →
   app tidak menampilkannya sebagai error, tapi membuka **layar update wajib**.
3. Saat start + kembali-foreground, app memanggil `GET /app/versi?versi=<versi>` (tanpa
   auth). Respons menentukan layar wajib / banner opsional.
4. Tombol **Update Sekarang**:
   - Desktop terpasang → `electron-updater` (unduh dalam app + progress → pasang & mulai ulang).
   - Android → plugin native `ApkUpdater` (DownloadManager + FileProvider install).
   - Peramban / dev / tak didukung → buka URL unduhan di peramban.

## Kontrak backend (WAJIB disediakan server)

### `GET /api/pos/v1/app/versi?versi=<versiApp>` — tanpa auth
```jsonc
{
  "success": true,
  "data": {
    "wajib": false,                 // true → layar penuh memblokir
    "update_tersedia": true,        // true & !wajib → banner (maks 1×/hari)
    "versi_terbaru": "0.9.9",
    "catatan": "Perbaikan pembayaran QRIS & keamanan.",  // dipakai apa adanya di layar
    "ukuran": 84213760,             // byte (opsional)
    "unduhan": {
      "windows": { "url": "https://pos.tatreport.com/unduh/Tuleh-Setup-0.9.9.exe" },
      "android": { "url": "https://pos.tatreport.com/unduh/Tuleh-0.9.9-android.apk" }
    }
  }
}
```

### HTTP `426` dari endpoint mana pun
Versi klien di bawah minimum. Body `message` (opsional) ditampilkan di layar wajib.

### Proksi unduhan `https://pos.tatreport.com/unduh/{nama}` — dukung HTTP Range
Melayani aset Release GitHub berdasarkan nama berkas. **Untuk electron-updater** harus juga
melayani `latest.yml` (dan `*.blockmap`) di path yang sama:
`https://pos.tatreport.com/unduh/latest.yml`. Jangan pernah menonaktifkan TLS.

Nama aset yang dihasilkan CI:
- Windows: `Tuleh-Setup-<versi>.exe`, `Tuleh-Setup-<versi>.exe.blockmap`, `latest.yml`
- Android: `Tuleh-<versi>-android.apk`

## GitHub Secrets (untuk signing APK rilis)

Tanpa ini, CI memakai `assembleDebug` (kunci berubah tiap build → update Android **tak bisa**
menimpa app lama). Buat keystore sekali, lalu isi 4 secret:

```bash
keytool -genkeypair -v -keystore tuleh-release.keystore \
  -alias tuleh -keyalg RSA -keysize 2048 -validity 10000
base64 -w0 tuleh-release.keystore   # → nilai ANDROID_KEYSTORE_BASE64
```

| Secret | Isi |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | keystore di-base64 |
| `ANDROID_KS_PASS` | password store |
| `ANDROID_KEY_ALIAS` | alias kunci (mis. `tuleh`) |
| `ANDROID_KEY_PASS` | password kunci |

> Simpan keystore & password baik-baik. **Kunci yang sama harus dipakai selamanya** —
> ganti kunci = pengguna wajib uninstall+install ulang.

## Berkas terkait

| Berkas | Peran |
|---|---|
| `frontend/src/main/api-client.js` | header versi + deteksi 426 (desktop) |
| `frontend/src/main/updater.js` | electron-updater (unduh/progress/pasang) |
| `frontend/src/main/ipc.js` | relay 426 + kanal `app:checkUpdate`/`update:*` |
| `frontend/src/preload/preload.js` | ekspos kanal update ke renderer |
| `frontend/src/renderer/js/update.js` | logika layar + orkestrasi unduh/pasang |
| `frontend/src/renderer/styles/update.css` | tampilan layar wajib + banner |
| `mobile/www-src/js/mobile-bridge.js` | header versi + 426 + jembatan installer Android |
| `mobile/native/ApkUpdaterPlugin.java` | plugin native: DownloadManager + FileProvider install |
| `mobile/native/MainActivity.java` | daftarkan plugin (menimpa hasil `cap add`) |
| `mobile/native/patch-android.py` | izin `REQUEST_INSTALL_PACKAGES` + jalur FileProvider |
| `mobile/native/apply-signing.py` | suntik signingConfig rilis dari Secrets |
| `.github/workflows/release.yml` | build + publish `latest.yml` + versionCode naik + signing |

## Matriks verifikasi

| Skenario | Server balas | Harapan |
|---|---|---|
| Versi terbaru | `wajib=false, update_tersedia=false` | Tidak ada layar/banner |
| Update opsional | `update_tersedia=true` | Banner bawah, bisa ditutup, muncul maks 1×/hari |
| Update wajib (start) | `wajib=true` | Layar penuh memblokir, tanpa tutup, Back ditelan |
| Update wajib (426) | `426` di request apa pun | Layar penuh memblokir muncul segera |
| Cek gagal (offline) | timeout/5xx | **Fail-open** — app tetap jalan, cek diam-diam diulang |
| Desktop terpasang → tombol | — | electron-updater: progress → pasang → mulai ulang |
| Android → tombol | — | minta izin bila perlu → unduh (progress) → pemasang sistem |
| Android tanpa izin | — | buka Setelan "Instal aplikasi tak dikenal", lalu "Coba Lagi" |
| Uji versi minimum | naikkan minimum di server | klien lama kena 426 → layar wajib |
| Downgrade | `versi_terbaru` < versi klien | tak ada update (klien lebih baru) |

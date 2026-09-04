# Tuléh — Aplikasi Kasir (POS) Modern

**Tuléh** adalah aplikasi **Point of Sale desktop** untuk UMKM Indonesia, berjalan
di atas **MOVERA POS API** (`https://tatreport.com`). Satu aplikasi, banyak bidang
usaha: menu & alur kerja menyesuaikan jenis toko secara otomatis (*manifest-driven*).

> 🧭 **POS universal** — minimarket dapat kasir cepat; F&B/bakso dapat Dapur (KDS) +
> antrian + pesan via QR meja; laundry dapat papan tahapan cuci–kering–lipat dengan
> pelacakan pelanggan. Cetak biru lengkap: [Blueprint-Universal-POS.md](Blueprint-Universal-POS.md).

## Struktur repo

| Folder | Teknologi | Isi |
|---|---|---|
| [`frontend/`](frontend) | Electron (vanilla ES modules, tanpa framework/bundler) | Aplikasi kasir desktop |
| [`backend/`](backend) | Go (stdlib murni, tanpa dependency) | Gateway lokal — proxy ke MOVERA API |
| [`mobile-flutter/`](mobile-flutter) | Flutter (Android, minSdk 29) | **Aplikasi Android utama** — native, Material 3, mode demo, cetak thermal Bluetooth |
| [`mobile/`](mobile) | Capacitor (Android) | **Legacy** — bungkus UI web desktop + jembatan API langsung; dipertahankan hanya untuk pengguna lama |

### Dua aplikasi Android — mana yang dipakai?

| | `mobile-flutter/` (utama) | `mobile/` (legacy) |
|---|---|---|
| Teknologi | Flutter native | WebView + UI web desktop |
| ID paket di ponsel | `com.tuleh.tuleh_pos` | `com.tuleh.kasir` |
| Rilis | tag `flutter-vX.Y.Z` ([flutter-release.yml](.github/workflows/flutter-release.yml)), APK per ABI | ikut rilis desktop `vX.Y.Z` sebagai `Tuleh-<versi>-android.apk` |
| Pembaruan di aplikasi | server `/app/versi` lalu GitHub Releases | server `/app/versi` (di-mirror MOVERA) |
| Status | dikembangkan aktif | beku — hanya perbaikan kritis |

Keduanya memakai **logo Tuléh yang sama** (notepad + pensil, sumber di `mobile/assets/`),
jadi bila kedua aplikasi terpasang di satu ponsel akan tampak dua ikon "Tuléh".
Pengguna aplikasi lama sebaiknya memasang versi Flutter lalu mencopot yang lama.
Rencana: hentikan build Capacitor dari rilis desktop setelah mirror MOVERA
(`SERVER-AUTO-UPDATE.md`) diarahkan ke APK Flutter.

Backend cloud sesungguhnya (Laravel/MOVERA) berada di `tatreport.com` — di luar repo
ini. `backend/` di sini adalah **gateway lokal** yang menyala otomatis saat aplikasi
dibuka: cache, rate-limit, dan allowlist endpoint di `127.0.0.1`.

```
Tuléh (Electron) ──HTTP──▶ gateway Go (127.0.0.1:8787) ──HTTPS──▶ tatreport.com (MOVERA)
```

## Menjalankan (mode pengembangan)

**Prasyarat:** Node.js ≥ 18. (Go ≥ 1.26 hanya bila ingin membangun ulang gateway.)

```powershell
cd frontend
npm install     # sekali saja — juga mengunduh font self-hosted (postinstall)
npm start
```

> Tanpa `npm install`? Bisa langsung: `npx --yes electron@35 .` dari folder `frontend/`.

Login memakai akun POS MOVERA Anda; server default `https://tatreport.com` (bisa
diganti per-tenant lewat **Ubah server** di layar login, wajib HTTPS). Ingin
melihat-lihat tanpa akun? Klik **Coba Mode Demo** — 6 toko contoh (minimarket,
bakso, laundry, bengkel, doorsmeer, salon/barbershop) dengan data simulasi lokal.

Gateway Go menyala otomatis; menjalankan manual (opsional) — lihat
[backend/README.md](backend/README.md):

```powershell
cd frontend
powershell -ExecutionPolicy Bypass -File tools\run-backend.ps1
```

## Uji (test)

```powershell
# Frontend (unit test: keranjang, format, tema, notifikasi, langganan, alur demo)
cd frontend
npm test

# Backend gateway (Go)
cd backend
go test ./...
```

## Build installer Windows (.exe)

```powershell
cd frontend
npm run dist        # electron-builder → dist/Tuleh-Setup-<versi>.exe
```

Installer membundel gateway Go (`resources/backend/`) sehingga pengguna akhir tidak
perlu menyetel apa pun. Ikon diambil dari `frontend/build/icon.png`.

## Fitur

- **POS universal (manifest-driven)** — menu & alur menyesuaikan bidang usaha toko.
- **Kasir** — katalog + scan barcode, diskon per item, pajak otomatis, TUNAI/
  TRANSFER/QRIS, uang cepat, struk thermal 80mm + **nomor antrian & QR lacak**.
  `F2` cari, `F4` bayar.
- **Bon meja / Open Bill** — dine-in bayar-di-akhir: buka meja, catat pesanan
  per ronde ke dapur, gabung meja, cetak pra-bon, bayar.
- **Papan Pesanan / KDS** — kolom kanban mengikuti tahapan toko, umur pesanan
  berwarna, transisi tervalidasi.
- **QR pelanggan** — pesan mandiri dari meja (`/o/{kode}`), lacak status
  (`/t/{token}`), papan antrian TV (`/antrian`) — via WiFi lokal atau **Akses
  Internet Publik** (Cloudflare Tunnel, gratis).
- **Stasiun, Produk, Pelanggan, Sesi kasir (rekap X/Z), Riwayat, Laporan (+CSV)**.
- **Tema terang & gelap** dengan tombol ganti tema + lonceng notifikasi.
- **Langganan & Kontak CS** — banner masa langganan + tombol Hubungi CS
  (fondasi Sistem Mitra/afiliasi).

## Pintasan keyboard (desktop)

Tekan **F1** di dalam aplikasi untuk daftar lengkap. Yang paling sering dipakai kasir:

| Tombol | Aksi |
|---|---|
| `F2` atau `/` | Fokus ke kolom cari / scan barcode |
| `Tab` (dari kolom cari) | Langsung ke produk pertama, lewati filter kategori |
| `↑ ↓ ← →`, `Home`, `End` | Pilih produk di katalog; `Enter`/`Spasi` menambahkan |
| `+` / `−` / `Delete` | Ubah jumlah / hapus baris (produk terpilih, atau baris terakhir) |
| `Esc` | Kosongkan pencarian → kembali ke Beranda; di layar lain: Beranda |
| `F4` atau `Ctrl+Enter` | Bayar · `F8` kosongkan keranjang |
| `F5` / `F6` / `F7` | Metode bayar ke-1/2/3 di jendela pembayaran |
| `Ctrl+0…9` | Beranda / pindah layar · `Ctrl+Shift+Q` keluar akun |

Mengetik huruf atau angka di mana pun pada layar kasir langsung mengisi kolom cari, jadi scanner barcode bekerja tanpa harus mengklik kolom itu dulu.

## Mode Demo: masa coba 7 hari

Mode Demo di desktop dan Android berlaku **7 hari** sejak pertama dibuka di perangkat itu, dihitung dengan **waktu server** (mengubah jam perangkat tidak berpengaruh; membuka demo pertama kali perlu koneksi). Setelah berakhir, aplikasi terkunci sampai masuk dengan akun berlangganan. Batas yang diketahui: menghapus aplikasi atau mereset perangkat mengulang masa coba; menutupnya butuh pendaftaran perangkat di server MOVERA.

## Arsitektur & keamanan

```
┌────────────────────────── Electron ──────────────────────────┐
│  Renderer (sandbox, CSP ketat, tanpa Node)                    │
│    └─ window.iposAPI  ← contextBridge (preload)               │
│  Main process                                                 │
│    ├─ ipc.js         → validasi semua input dari renderer     │
│    ├─ api-client.js  → HTTPS ke MOVERA API (timeout 15 dtk)   │
│    └─ auth-store.js  → token terenkripsi safeStorage (DPAPI)  │
└───────────────────────────────────────────────────────────────┘
```

- Token **tidak pernah** menyentuh renderer; tersimpan terenkripsi via `safeStorage`
  (DPAPI Windows).
- Renderer `sandbox: true` + `contextIsolation`, tanpa `nodeIntegration`.
- CSP `default-src 'none'` — seluruh HTTP lewat main process.
- Navigasi keluar & `window.open` diblokir; tautan https dibuka di browser OS.
- Semua data API di-escape sebelum masuk DOM (anti-XSS).
- Gateway Go: bind `127.0.0.1`, allowlist endpoint, rate-limit, token di-hash
  SHA-256 di cache, tidak pernah ditulis ke log.

## Dokumentasi

- [Blueprint-Universal-POS.md](Blueprint-Universal-POS.md) — visi & roadmap POS universal.
- [Docs-API.md](Docs-API.md) — konvensi & endpoint MOVERA POS API.

## Lisensi

MIT.

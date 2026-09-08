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
- **Display Pelanggan** (monitor kedua desktop, halaman LAN `/display`, atau
  overlay Android) — keranjang & total live; saat kasir memilih **QRIS** tampil
  gambar QR (statis atau QRIS otomatis) dan saat **TRANSFER** tampil daftar
  rekening dari Pengaturan → Pembayaran, sehingga pelanggan bisa membayar tanpa
  melihat layar kasir.
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
| `F9` / `F10` | Parkir keranjang (simpan, lanjutkan nanti) / buka daftar keranjang terparkir |
| `F5` / `F6` / `F7` | Metode bayar ke-1/2/3 di jendela pembayaran |
| `Ctrl+0…9` | Beranda / pindah layar · `Ctrl+Shift+Q` keluar akun |

Mengetik huruf atau angka di mana pun pada layar kasir langsung mengisi kolom cari, jadi scanner barcode bekerja tanpa harus mengklik kolom itu dulu.

**Pemindai barcode kamera** (Flutter ≥ 2.14.0): ikon pindai di Kasir membuka kamera (mobile_scanner, model disertakan) dalam mode beruntun, barcode yang dikenal langsung masuk keranjang; form produk punya tombol pindai untuk kolom barcode.

**Tablet Android** (Flutter ≥ 2.13.0): pada layar ≥ 720 dp aplikasi memakai rail samping dan tata letak ala desktop: kasir dua panel (katalog grid + keranjang menetap, langkah bayar di panel), riwayat master-detail, beranda dua kolom, daftar lain berlebar terbatas; lembar (hasil transaksi, pilih pelanggan, menu Lainnya) tampil sebagai dialog. Ambang dan pembungkusnya ada di `mobile-flutter/lib/core/layout/lebar.dart`.

**Display Pelanggan saat bayar** (desktop ≥ 0.9.18): begitu kasir memilih metode di jendela pembayaran, display (jendela kedua maupun halaman LAN di tablet/HP) menampilkan panel metode itu: tunai (total, lalu uang diterima & kembalian saat diketik), QRIS (kode untuk dipindai, atau arahan bila gambar QR belum diunggah), transfer (daftar rekening). Layar potret menaruh panel di bawah pesanan.

**Diskon transaksi** (desktop ≥ 0.9.20): kolom persen di ringkasan keranjang; digabung dengan diskon baris menjadi satu `diskon_persen` per item (10% lalu 10% = 19%), ikut tersimpan saat keranjang diparkir dan tampil di Display Pelanggan.

**Parkir keranjang** (desktop ≥ 0.9.17, Android ≥ 2.17.0): keranjang yang belum dibayar bisa diparkir (desktop: tombol Parkir / `F9`, lalu **Tersimpan** / `F10`; Android: ikon parkir di keranjang, daftarnya di ikon parkir bilah atas Kasir), disimpan per toko di perangkat kasir, paling banyak 20, lengkap dengan pelanggan/diskon/catatan. Melanjutkan saat keranjang masih berisi menawarkan pilihan *parkir dulu* atau *ganti*. **Bagikan struk**: setelah bayar dan dari Riwayat, struk bisa dikirim lewat WhatsApp (teks 32 kolom seperti struk thermal) atau disalin. Di Android (≥ 2.10.0) tersedia **Cetak ulang** dan **Bagikan** dari detail Riwayat, tombol Bagikan di lembar hasil transaksi, pilihan **Tampilan** (ikuti sistem / terang / gelap) di Pengaturan, dan aksi cepat Pengeluaran di Beranda. Sejak Android 2.18.0 layar Laporan punya **Bagikan ringkasan** (teks omzet/laba/omzet harian/rekap kasir; ditutup di Mode Demo seperti ekspor laporan desktop). Sejak Android 2.17.0 detail Riwayat punya **Batalkan transaksi** (online saja; stok kembali & penjualan keluar dari laporan — transaksi yang belum sinkron dibatalkan lewat Pengaturan → Sinkronisasi) dan detail produk punya **Opname stok** (`POST /inventory/opname`, bisa diantrekan saat offline seperti stok masuk). Sejak Android 2.11.0 keranjang punya kartu **Pelanggan / Diskon transaksi / Catatan**: diskon persen diterapkan ke setiap baris (`items.*.diskon_persen`), pelanggan dikirim sebagai `id_pelanggan`, catatan sebagai `catatan`, sama dengan kasir desktop; struk memuat pelanggan dan potongan diskon.

## Mode Demo: masa coba 7 hari

Mode Demo di desktop dan Android berlaku **7 hari** sejak pertama dibuka di perangkat itu, dihitung dengan **waktu server** (mengubah jam perangkat tidak berpengaruh; membuka demo pertama kali perlu koneksi). Setelah berakhir, aplikasi terkunci sampai masuk dengan akun berlangganan.

**Printer struk** (desktop ≥ 0.9.22): Pengaturan → Printer struk memuat daftar printer Windows; pilih printer thermal, centang *cetak langsung tanpa dialog* agar struk keluar tanpa jendela cetak, dan *cetak otomatis setelah pembayaran* agar struk langsung tercetak begitu transaksi tercatat (termasuk struk lokal saat offline). Tombol **Uji cetak** dan **Uji lewat dialog** mencetak struk contoh; preferensi disimpan di `settings.json` (`cetak`). Bila printer pilihan dicabut, aplikasi memberi tahu dan jatuh ke dialog Windows.

Selama demo, beberapa hal sengaja dibatasi (desktop ≥ 0.9.17, Android ≥ 2.10.0) agar demo tetap untuk mencoba, bukan berjualan: struk cetak/pratinjau/teks bertanda **MODE DEMO — bukan bukti pembayaran**; paling banyak **20 transaksi per hari** (checkout kasir & bayar bon meja) yang dibuat pengguna; di desktop, ekspor CSV laporan, PDF & bagikan WhatsApp laporan keuangan, dan akses internet publik (tunnel) tidak tersedia. Data contoh tetap bisa dijelajahi seluruhnya.

Tiga lapis: catatan lokal bertanda (sudah aktif), pendaftaran perangkat di server, dan identitas lewat OTP WhatsApp/email. Lapis 2 dan 3 sudah ada di aplikasi (desktop ≥ 0.9.14, Android ≥ 2.6.0) dan aktif otomatis begitu server MOVERA memasang endpoint di [KONTRAK-MASA-COBA.md](KONTRAK-MASA-COBA.md); sebelum itu hanya lapis lokal yang berlaku, sehingga menghapus aplikasi masih mengulang masa coba.

## Mode offline (desktop)

Sejak desktop 0.9.19 aplikasi Windows punya mode offline yang sama dengan Android fase 1–2, dikerjakan di proses utama Electron tanpa dependensi native: setiap jawaban GET terautentikasi disalin ke `userData/offline/salinan.json` (per toko + jalur + query, maks 600 entri) dan disajikan saat jaringan gagal, dengan pita "Offline · menampilkan data terakhir HH:MM" di bawah topbar; identitas hasil masuk disalin sebagai `/auth/me` sehingga aplikasi tetap bisa dibuka tanpa internet. Checkout (kecuali QRIS otomatis), pengeluaran, dan stok masuk yang gagal jaringan diantrekan di `antrean.json` beserta `client_ref`/`waktu_klien`, struk lokal bernomor `L-yyMMdd-NNNN` (tampil di Riwayat berstatus BELUM SINKRON, bisa dicetak), lalu dikirim FIFO ketat dengan mundur eksponensial begitu server terjangkau; penolakan server atau timeout setelah kirim masuk *perlu ditinjau* di Pengaturan → Sinkronisasi (Kirim ulang / Batalkan). Keluar akun ditahan bila antrean berisi. Jalur uji: `IPOS_SMOKE_OFFLINE=1` memutus jaringan pura-pura, `IPOS_SMOKE_USER/PASS` mengisi formulir masuk.

## Mode offline (Android)

Sejak Android 2.7.0 aplikasi menyimpan salinan setiap jawaban baca dari server di SQLite (`drift`). Saat internet mati, layar tetap menampilkan data terakhir dengan pita "Offline · menampilkan data terakhir HH:MM"; begitu server terjangkau lagi, data dimuat ulang (fase 1).

Sejak 2.8.0 (fase 2) transaksi, pengeluaran, dan stok masuk yang dibuat saat offline masuk **antrean kirim** di SQLite (`outbox`, dengan `client_ref` + `waktu_klien`) dan dikirim otomatis berurutan (FIFO ketat, mundur eksponensial 5s→10m) begitu server terjangkau. Struk offline memakai nomor sementara `L-yyMMdd-NNNN`, stok katalog langsung memperhitungkan penjualan tertunda, riwayat menandai transaksi "belum tersinkron". Baris yang server tolak, atau yang timeout **setelah** data terkirim, berstatus *perlu ditinjau* di Pengaturan → Sinkronisasi (Kirim ulang / Batalkan) agar tidak terjadi transaksi ganda sebelum server mengenali `client_ref`. Keluar akun ditahan bila antrean belum kosong.

Sejak 2.9.0 (fase 3) **sesi kasir** dan **bon meja** ikut offline: buka sesi diantrekan (`SESI_BUKA`, `gudang_id` diisi tepat sebelum kirim bila belum tersalin) dan tampil sebagai "Sesi offline" sampai terkirim; tutup sesi ditahan selama antrean toko belum kosong. Buka bon, ronde, dan bayar bon diantrekan (`BILL_BUKA`/`BILL_RONDE`/`BILL_BAYAR`); bon yang lahir offline memakai id `lokal:<client_ref>` di path dan pengurai menggantinya dengan id server dari hasil baris induk (FIFO menjamin induk lebih dulu; induk yang belum terkirim membuat turunannya *perlu ditinjau*, Kirim ulang induk memulihkannya). Nama/harga item ronde disimpan di kunci `_tampilan` yang dibuang sebelum kirim. Sejak 2.15.0 antrean juga diproses di latar belakang lewat WorkManager (`core/offline/sinkron_latar.dart`): tugas sekali jalan didaftarkan tiap ada yang diantrekan (syarat jaringan tersambung) plus tugas berkala 15 menit; isolate latar membuka SQLite yang sama dan mengalah bila aplikasi sedang menguraikan (kunci berkas `pengurai.lock`, kedaluwarsa 3 menit). Sejak 2.16.0 (dan desktop 0.9.21) baris TINJAU akibat timeout-setelah-kirim dipulihkan otomatis (`pemulih_tinjau.dart` / `offline/pemulih.js`): dicocokkan ke `GET /transaksi` hari itu — satu cocok (total, metode, ±15 menit, tak dibatalkan, belum diklaim) → TERKIRIM dengan nomor server; tak ada → MENUNGGU dan dikirim ulang di putaran yang sama; ganda → tetap TINJAU dengan petunjuk. Stok lokal untuk bon meja dipotong saat BILL_BAYAR dari ronde yang masih di antrean. Belum: pemulihan lewat `client_ref` (menunggu server).

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

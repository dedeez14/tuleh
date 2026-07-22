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
melihat-lihat tanpa akun? Klik **Coba Mode Demo** — 3 toko contoh (minimarket,
bakso, laundry) dengan data simulasi lokal.

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

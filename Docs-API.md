# MOVERA POS API — Panduan Lengkap & Demo

Panduan integrasi **REST API** untuk aplikasi POS terpisah (Flutter desktop/Android,
web, atau integrator pihak ketiga) yang mengonsumsi backend MOVERA. Dokumen ini
mencakup: base URL, autentikasi, **akun demo siap pakai**, format respons, referensi
seluruh endpoint dengan contoh nyata, dan alur transaksi ujung-ke-ujung.

> Dokumen ringkas versi lama: [pos-api.md](pos-api.md).
> Spesifikasi mesin (OpenAPI 3.0) & Swagger UI interaktif: lihat [§11](#11-dokumentasi-interaktif-swagger--openapi).

---

## Daftar Isi

1. [Base URL & Tenant](#1-base-url--tenant)
2. [Akun Demo (siap pakai)](#2-akun-demo-siap-pakai)
3. [Autentikasi](#3-autentikasi)
4. [Format Respons & Kode Status](#4-format-respons--kode-status)
5. [ID Terenkripsi](#5-id-terenkripsi)
6. [Referensi Endpoint](#6-referensi-endpoint)
7. [Alur Transaksi Ujung-ke-Ujung](#7-alur-transaksi-ujung-ke-ujung)
8. [Katalog Data Demo](#8-katalog-data-demo)
9. [Batas Laju (Rate Limit) & Token](#9-batas-laju-rate-limit--token)
10. [Catatan & Known Issues](#10-catatan--known-issues)
11. [Dokumentasi Interaktif (Swagger / OpenAPI)](#11-dokumentasi-interaktif-swagger--openapi)

---

## 1. Base URL & Tenant

API me-resolve **tenant per-domain**. Arahkan base URL ke domain perusahaan; tenant
+ company ditentukan otomatis dari domain + token login. Tidak perlu mengirim tenant ID.

```
https://<domain-perusahaan>/api/pos/v1
```

| Lingkungan | Base URL |
|------------|----------|
| Perusahaan utama (central) | `https://tatreport.com/api/pos/v1` |
| Tenant (subdomain) | `https://<subdomain>.tatreport.com/api/pos/v1` |

Semua contoh di dokumen ini memakai `https://tatreport.com/api/pos/v1`.

Cek konektivitas tanpa autentikasi:

```bash
curl -s https://tatreport.com/api/pos/v1/ping
# {"success":true,"data":{"app":"MOVERA POS API","version":"v1","time":"2026-07-05T13:47:34+07:00"},"message":""}
```

---

## 2. Akun Demo (siap pakai)

Sebuah perusahaan uji lengkap sudah disiapkan (CoA, 20 produk bergambar, 5 kategori,
7 satuan, 4 pelanggan, 1 gudang, 1 toko POS). **Langsung bisa login.**

| Field | Nilai |
|-------|-------|
| Base URL | `https://tatreport.com/api/pos/v1` |
| Login (email) | `admin-pos-test@movera.test` |
| Password | `PASSWORD_DEMO` |
| Device name | bebas, mis. `Kasir-01` |
| Perusahaan | **TES POS** (Minimarket) |
| Toko POS | **Minimarket TES** (`bidang_usaha_code = minimarket`) |

Login cepat & simpan token:

```bash
curl -s -X POST https://tatreport.com/api/pos/v1/auth/login \
  -H "Content-Type: application/json" -H "Accept: application/json" \
  -d '{"login":"admin-pos-test@movera.test","password":"PASSWORD_DEMO","device_name":"Kasir-01"}'
```

> Untuk aplikasi MOVERA POS (Flutter): pada layar login, isi **Server** =
> `https://tatreport.com`, lalu email/password di atas. Aplikasi menambahkan
> `/api/pos/v1` secara otomatis.

---

## 3. Autentikasi

Berbasis token **Laravel Sanctum (Bearer)**. Login mengembalikan token; sertakan di
header `Authorization: Bearer <token>` untuk semua endkoin lain, plus
`Accept: application/json`.

### `POST /auth/login`

Body:

```json
{ "login": "admin-pos-test@movera.test", "password": "PASSWORD_DEMO", "device_name": "Kasir-01" }
```

Respons `200` (dipangkas — `permissions` bisa panjang):

```json
{
  "success": true,
  "data": {
    "token": "20|jmzV1PAIj2G5Kx7Xfn12Nq832S30a7wAYX5x2U5dde6ca548",
    "token_type": "Bearer",
    "user": { "id": "<enc>", "name": "Dede Febriansyah", "email": "admin-pos-test@movera.test", "is_admin": true },
    "company": { "id": "<enc>", "nama": "TES POS", "alamat": "…kepanjen", "telepon": null, "npwp": null, "logo": null },
    "branch": { "id": "<enc>", "nama": "Cabang Default" },
    "permissions": ["dashboard.view", "umum.company.view", "…"],
    "modules": { "multi_satuan": true },
    "payment_methods": ["TUNAI", "TRANSFER", "QRIS"]
  },
  "message": ""
}
```

**Syarat akses POS**: user adalah admin **atau** memiliki permission `pos.view`
(dapat dikonfigurasi via `POS_API_PERMISSION`).

Error: `401` kredensial salah · `403` tidak punya akses POS · `404` modul POS nonaktif ·
`429` throttle (maks **5 percobaan/menit per IP**).

### `GET /auth/me`

Konteks user + company + branch + **sesi kasir aktif** (jika ada). Panggil saat aplikasi
dibuka untuk mengembalikan state.

```bash
curl -s https://tatreport.com/api/pos/v1/auth/me -H "Authorization: Bearer $TOKEN" -H "Accept: application/json"
```

### `POST /auth/logout`

Mencabut (revoke) token yang sedang dipakai.

```bash
curl -s -X POST https://tatreport.com/api/pos/v1/auth/logout -H "Authorization: Bearer $TOKEN" -H "Accept: application/json"
```

---

## 4. Format Respons & Kode Status

Semua respons memakai amplop seragam:

```json
{ "success": true, "data": <payload>, "message": "" }
```

Endpoint list menambahkan `meta` untuk paginasi:

```json
{ "success": true, "data": [ … ], "meta": { "current_page": 1, "last_page": 7, "per_page": 3, "total": 20 } }
```

Kegagalan:

```json
{ "success": false, "message": "Pesan kesalahan yang bisa ditampilkan." }
```

Kegagalan validasi (`422`) menyertakan `errors`:

```json
{ "success": false, "message": "…", "errors": { "field": ["pesan"] } }
```

| Kode | Arti |
|------|------|
| `200` | Sukses |
| `401` | Token tidak ada/tidak valid |
| `403` | Tidak punya akses (permission/modul) |
| `404` | Sumber daya tidak ditemukan / modul nonaktif |
| `409` | Konflik status (mis. checkout tanpa sesi terbuka) |
| `422` | Validasi gagal |
| `429` | Throttle terlampaui |
| `500` | Server error |

---

## 5. ID Terenkripsi

Setiap ID entitas dikembalikan sebagai **string terenkripsi** (bukan integer), mis.
`"ZXlKcGRpSTZJbWwyYVhkMWREQkJaa3B0WlhaTFFWQm9ORTk0UVZFOVBTSXNJblpoYkhWbElqb2lhM0ZhWlV0RmNFSTBWbFptV0hwTGFtZ3ZiMGg0VVQwOSJ9…"`.

Aturan:

- **Kirim balik nilai terenkripsi apa adanya** saat merujuk entitas (mis.
  `id_produk`, `id_pelanggan`, `gudang_id`). Server mendekripsinya otomatis.
- Jangan mem-parse atau menebak integer di baliknya.
- Path parameter `{id}` juga memakai nilai terenkripsi.

Contoh: item checkout memakai `id_produk` = nilai `id` yang dikembalikan `GET /produk`.

---

## 6. Referensi Endpoint

Semua endpoint di bawah prefix `/api/pos/v1` dan (kecuali `ping`, `openapi.yaml`,
`auth/login`) butuh header `Authorization: Bearer <token>`.

### 6.1 Ringkasan

| Grup | Method | Path | Fungsi |
|------|--------|------|--------|
| Sistem | GET | `/ping` | Cek konektivitas (tanpa auth) |
| Auth | POST | `/auth/login` | Login → token |
| Auth | GET | `/auth/me` | Konteks user + sesi aktif |
| Auth | POST | `/auth/logout` | Cabut token |
| Konfig | GET | `/config` | Konfig perusahaan + metode bayar |
| Konfig | GET | `/bidang-usaha` | Daftar vertical/bidang usaha |
| Toko | GET | `/tokos` | Daftar toko POS |
| Toko | POST | `/tokos` | Buat toko POS |
| Toko | GET | `/tokos/{id}` | Detail toko |
| Toko | GET | `/tokos/{id}/manifest` | Manifest UI toko (menu, kapabilitas) |
| Produk | GET | `/produk` | Daftar produk (paginasi, cari, filter) |
| Produk | GET | `/produk/barcode/{barcode}` | Cari 1 produk via barcode |
| Produk | GET | `/produk/{id}` | Detail produk |
| Master | GET | `/kategori` | Daftar kategori |
| Master | GET | `/gudang` | Daftar gudang ⚠️ (lihat [§10](#10-catatan--known-issues)) |
| Master | GET | `/satuan` | Daftar satuan |
| Pelanggan | GET | `/pelanggan` | Daftar pelanggan (cari) |
| Pelanggan | GET | `/pelanggan/{id}` | Detail pelanggan |
| Pelanggan | POST | `/pelanggan` | Tambah pelanggan |
| Sesi | GET | `/sesi/aktif` | Rekap sesi kasir terbuka (atau `null`) |
| Sesi | GET | `/sesi` | Riwayat sesi |
| Sesi | POST | `/sesi/buka` | Buka sesi kasir |
| Sesi | POST | `/sesi/{id}/tutup` | Tutup sesi kasir |
| Sesi | GET | `/sesi/{id}/rekap` | Rekap X/Z sesi |
| Sesi | GET | `/sesi/{id}` | Detail sesi |
| Transaksi | POST | `/transaksi/checkout` | Buat penjualan |
| Transaksi | GET | `/transaksi` | Riwayat transaksi |
| Transaksi | GET | `/transaksi/{id}` | Detail transaksi |
| Transaksi | GET | `/transaksi/{id}/struk` | Struk untuk cetak |
| Transaksi | POST | `/transaksi/{id}/batal` | Batalkan transaksi |
| Order | GET/POST | `/orders`, `/orders/{id}`, `/orders/{id}/transition` | Siklus order (F&B/jasa) |
| Sinkron | POST | `/sync/batch` | Kirim antrean transaksi offline |
| Laporan | GET | `/laporan/penjualan-harian` | Rekap penjualan harian |
| Laporan | GET | `/laporan/penjualan-produk` | Produk terlaris |
| Laporan | GET | `/laporan/stok` | Posisi stok |
| Laporan | GET | `/laporan/rekap-kasir` | Rekap per kasir |

### 6.2 `GET /config`

```json
{
  "success": true,
  "data": {
    "company": { "id": "<enc>", "nama": "TES POS", "alamat": "…", "telepon": null, "npwp": null, "logo": null },
    "pengaturan": { "stok_minimum_tampil": 0, "tampilkan_stok_habis": true },
    "payment_methods": ["TUNAI", "TRANSFER", "QRIS"],
    "modules": { "multi_satuan": true }
  }, "message": ""
}
```

### 6.3 `GET /tokos`

```json
{
  "success": true,
  "data": [{
    "id": "<enc>", "nama": "Minimarket TES",
    "bidang_usaha": { "code": "minimarket", "nama": "Minimarket / Toko Kelontong", "kategori": "Retail", "archetype": "inventory_sale" },
    "manifest_version": 1, "is_active": true
  }], "message": ""
}
```

### 6.4 `GET /produk`

Query params:

| Param | Tipe | Ket. |
|-------|------|------|
| `q` | string | Cari nama / kode / barcode |
| `kategori_id` | string(enc) | Filter kategori |
| `gudang_id` | string(enc) | Hitung stok pada gudang tertentu |
| `per_page` | int | Default 50, maks 100 |
| `page` | int | Halaman |

Contoh:

```bash
curl -s "https://tatreport.com/api/pos/v1/produk?q=aqua&per_page=3" \
  -H "Authorization: Bearer $TOKEN" -H "Accept: application/json"
```

Respons (1 item dari `data`):

```json
{
  "id": "<enc>",
  "kode": "MNM-001",
  "nama": "Aqua Botol 600ml",
  "barcode": "8993675001201",
  "harga_jual": 4000,
  "pajak_persen": 0,
  "satuan": "Botol",
  "satuan_id": "<enc>",
  "kategori": "Minuman",
  "kelola_stok": true,
  "stok": 120,
  "gambar": "https://tatreport.com/storage/produk/mnm-001.png"
}
```

- **`gambar`** adalah URL absolut siap dipakai `Image.network(...)` — sudah terverifikasi
  mengembalikan `HTTP 200` (PNG). Bernilai `null` bila produk tak punya gambar.
- **`stok`** = jumlah on-hand (SUM lapisan stok); mengikuti `gudang_id` bila dikirim.

### 6.5 `GET /produk/barcode/{barcode}`

Untuk pemindai barcode. Mengembalikan 1 produk atau `404`.

```bash
curl -s "https://tatreport.com/api/pos/v1/produk/barcode/8993675001201" \
  -H "Authorization: Bearer $TOKEN" -H "Accept: application/json"
```

### 6.6 `GET /kategori`, `GET /satuan`

Bentuk seragam `{ id(enc), kode, nama }`:

```json
{ "success": true, "data": [ { "id": "<enc>", "kode": "MKN", "nama": "Makanan Ringan" } ], "message": "" }
```

### 6.7 `GET /pelanggan`

Query `q` untuk pencarian. Item: `{ id(enc), kode, nama, telepon }`.

```json
{ "success": true, "data": [ { "id": "<enc>", "kode": "PLG-001", "nama": "Budi Santoso", "telepon": "081234567001" } ], "message": "" }
```

`POST /pelanggan` menambah pelanggan baru — body minimal `{ "nama": "…", "telepon": "…" }`,
mengembalikan pelanggan terenkripsi.

### 6.8 `POST /sesi/buka`

Membuka sesi kasir (wajib sebelum checkout).

| Field | Tipe | Wajib | Ket. |
|-------|------|-------|------|
| `gudang_id` | string(enc) | ✓ | Gudang sumber stok |
| `kas_awal` | number | ✓ | Saldo kas awal laci |
| `catatan` | string | – | Maks 255 |

```bash
curl -s -X POST https://tatreport.com/api/pos/v1/sesi/buka \
  -H "Authorization: Bearer $TOKEN" -H "Accept: application/json" -H "Content-Type: application/json" \
  -d '{"gudang_id":"<enc-gudang>","kas_awal":200000,"catatan":"Shift pagi"}'
```

### 6.9 `GET /sesi/aktif` & `GET /sesi/{id}/rekap`

Mengembalikan rekap sesi (X/Z report), atau `data: null` bila tak ada sesi terbuka:

```json
{
  "success": true,
  "data": {
    "nomor": "SESI/202607/0001", "status": "BUKA", "kasir": "Dede Febriansyah",
    "gudang_id": "<enc>", "waktu_buka": "2026-07-05T09:41:05+07:00", "waktu_tutup": null,
    "kas_awal": 200000, "total_tunai": 0, "total_transfer": 0, "total_qris": 0,
    "total_penjualan": 0, "jumlah_transaksi": 0,
    "kas_akhir_sistem": 200000, "kas_akhir_fisik": null, "selisih": null
  }, "message": ""
}
```

### 6.10 `POST /transaksi/checkout`

Membuat penjualan. **Butuh sesi kasir terbuka** (jika tidak → `409`).

Body:

| Field | Tipe | Wajib | Ket. |
|-------|------|-------|------|
| `items` | array | ✓ | Minimal 1 |
| `items[].id_produk` | string(enc) | ✓ | `id` dari `GET /produk` |
| `items[].harga` | number | ✓ | Harga satuan |
| `items[].kuantitas` | number | ✓ | Min 0.001 |
| `items[].diskon_persen` | number | – | 0–100 |
| `items[].pajak_persen` | number | – | 0–100 |
| `tipe_pembayaran` | enum | ✓ | `TUNAI` \| `TRANSFER` \| `QRIS` |
| `dibayar` | number | ✓ | Uang diterima (untuk kembalian) |
| `id_pelanggan` | string(enc) | – | Kosong = umum |
| `catatan` | string | – | Maks 500 |

```bash
curl -s -X POST https://tatreport.com/api/pos/v1/transaksi/checkout \
  -H "Authorization: Bearer $TOKEN" -H "Accept: application/json" -H "Content-Type: application/json" \
  -d '{
    "items": [
      { "id_produk": "<enc-aqua>",     "harga": 4000, "kuantitas": 2, "diskon_persen": 0,  "pajak_persen": 0 },
      { "id_produk": "<enc-bengbeng>", "harga": 2500, "kuantitas": 1, "diskon_persen": 10, "pajak_persen": 0 }
    ],
    "tipe_pembayaran": "TUNAI",
    "dibayar": 20000
  }'
```

Respons `200` (bentuk **struk**, contoh representatif):

```json
{
  "success": true,
  "data": {
    "id": "<enc>", "nomor": "POS/202607/0001", "tanggal": "2026-07-05T09:42:10+07:00",
    "status": "LUNAS", "pelanggan": null, "kasir": "Dede Febriansyah", "tipe_pembayaran": "TUNAI",
    "subtotal": 10500, "total_diskon": 250, "total_pajak": 0, "grand_total": 10250,
    "dibayar": 20000, "kembalian": 9750,
    "items": [
      { "nama": "Aqua Botol 600ml", "kuantitas": 2, "satuan": "Botol", "harga": 4000, "diskon_persen": 0, "pajak_persen": 0, "subtotal": 8000 },
      { "nama": "Beng-Beng Wafer", "kuantitas": 1, "satuan": "Bungkus", "harga": 2500, "diskon_persen": 10, "pajak_persen": 0, "subtotal": 2250 }
    ]
  }, "message": ""
}
```

Checkout otomatis: mengurangi stok (lapisan), membuat jurnal (jika `auto_posting` aktif),
dan menghitung `kembalian`.

### 6.11 `GET /transaksi`, `/{id}/struk`, `POST /{id}/batal`

- `GET /transaksi?dari=YYYY-MM-DD&sampai=YYYY-MM-DD&sesi_id=<enc>` — riwayat.
- `GET /transaksi/{id}/struk` — payload struk (sama seperti respons checkout).
- `POST /transaksi/{id}/batal` — membatalkan (mengembalikan stok & jurnal balik).

### 6.12 Laporan

```bash
curl -s "https://tatreport.com/api/pos/v1/laporan/penjualan-harian" -H "Authorization: Bearer $TOKEN" -H "Accept: application/json"
```

```json
{ "success": true, "data": { "rows": [], "total": { "jumlah_transaksi": 0, "total_omzet": 0, "rata_rata": 0 } }, "message": "" }
```

Tersedia juga `/laporan/penjualan-produk` (terlaris), `/laporan/stok`, `/laporan/rekap-kasir`.

---

## 7. Alur Transaksi Ujung-ke-Ujung

Skrip bash lengkap (login → buka sesi → checkout → rekap):

```bash
BASE="https://tatreport.com/api/pos/v1"

# 1) Login
TOKEN=$(curl -s -X POST "$BASE/auth/login" -H "Content-Type: application/json" -H "Accept: application/json" \
  -d '{"login":"admin-pos-test@movera.test","password":"PASSWORD_DEMO","device_name":"Kasir-01"}' \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['data']['token'])")
AUTH="Authorization: Bearer $TOKEN"; ACC="Accept: application/json"; CT="Content-Type: application/json"

# 2) Ambil gudang (untuk buka sesi)  ⚠️ lihat Known Issues bila 500
GID=$(curl -s "$BASE/gudang" -H "$AUTH" -H "$ACC" | python3 -c "import sys,json;print(json.load(sys.stdin)['data'][0]['id'])")

# 3) Buka sesi
curl -s -X POST "$BASE/sesi/buka" -H "$AUTH" -H "$ACC" -H "$CT" \
  -d "{\"gudang_id\":\"$GID\",\"kas_awal\":200000}"

# 4) Ambil 1 produk
P=$(curl -s "$BASE/produk?per_page=1" -H "$AUTH" -H "$ACC")
PID=$(echo "$P" | python3 -c "import sys,json;print(json.load(sys.stdin)['data'][0]['id'])")
HRG=$(echo "$P" | python3 -c "import sys,json;print(json.load(sys.stdin)['data'][0]['harga_jual'])")

# 5) Checkout tunai
curl -s -X POST "$BASE/transaksi/checkout" -H "$AUTH" -H "$ACC" -H "$CT" \
  -d "{\"items\":[{\"id_produk\":\"$PID\",\"harga\":$HRG,\"kuantitas\":1}],\"tipe_pembayaran\":\"TUNAI\",\"dibayar\":$HRG}"

# 6) Rekap sesi (X report)
curl -s "$BASE/sesi/aktif" -H "$AUTH" -H "$ACC"
```

---

## 8. Katalog Data Demo

**5 kategori** · **7 satuan** (PCS, BTL, KLG, BKS, SCH, KTK, KRG) · **4 pelanggan**
(PLG-001 Budi Santoso, PLG-002 Siti Aminah, PLG-003 Warung Bu Yati, PLG-004 Agus Setiawan) ·
**1 gudang** (Gudang Toko) · **20 produk** (semua bergambar):

| Kode | Nama | Kategori | Satuan | Barcode | Jual | Stok |
|------|------|----------|--------|---------|-----:|-----:|
| MNM-001 | Aqua Botol 600ml | Minuman | Botol | 8993675001201 | 4.000 | 120 |
| MNM-002 | Teh Botol Sosro 450ml | Minuman | Botol | 8992761100202 | 5.000 | 90 |
| MNM-003 | Coca-Cola Kaleng 330ml | Minuman | Kaleng | 8992222300303 | 7.000 | 60 |
| MNM-004 | Kopi Kapal Api Special | Minuman | Sachet | 8991002100404 | 2.000 | 200 |
| MNM-005 | Ultra Milk Coklat 250ml | Minuman | Kotak | 8998009000505 | 6.500 | 75 |
| MKN-001 | Chitato Sapi Panggang 68g | Makanan Ringan | Bungkus | 8992388100601 | 10.000 | 50 |
| MKN-002 | Oreo Coklat 133g | Makanan Ringan | Bungkus | 8993002100702 | 9.500 | 45 |
| MKN-003 | Beng-Beng Wafer | Makanan Ringan | Bungkus | 8992388100803 | 2.500 | 150 |
| MKN-004 | SilverQueen Cashew 65g | Makanan Ringan | Bungkus | 8999999100904 | 13.000 | 40 |
| MKN-005 | Roma Kelapa 300g | Makanan Ringan | Bungkus | 8991002101005 | 7.500 | 55 |
| SMB-001 | Beras Pandan Wangi 5kg | Sembako | Karung | 2000000001101 | 68.000 | 30 |
| SMB-002 | Minyak Goreng Bimoli 2L | Sembako | Botol | 8992222301202 | 38.000 | 40 |
| SMB-003 | Gula Pasir Gulaku 1kg | Sembako | Bungkus | 8992761101303 | 17.000 | 60 |
| SMB-004 | Indomie Goreng | Sembako | Bungkus | 8992388101404 | 3.500 | 300 |
| SMB-005 | Telur Ayam Negeri (kg) | Sembako | Karung | 2000000001505 | 29.000 | 50 |
| PWT-001 | Pepsodent Pasta Gigi 190g | Perawatan Diri | Pieces | 8999999101601 | 12.000 | 45 |
| PWT-002 | Lifebuoy Sabun Mandi 85g | Perawatan Diri | Pieces | 8999999101702 | 4.500 | 80 |
| PWT-003 | Sunsilk Shampoo Sachet | Perawatan Diri | Sachet | 8999999101803 | 1.000 | 250 |
| RTG-001 | Rinso Deterjen 770g | Rumah Tangga | Bungkus | 8999999101904 | 19.000 | 40 |
| RTG-002 | Sunlight Pencuci Piring 755ml | Rumah Tangga | Botol | 8999999102005 | 16.000 | 50 |

Gambar produk: `https://tatreport.com/storage/produk/<kode-huruf-kecil>.png`
(mis. `mnm-001.png`).

---

## 9. Batas Laju (Rate Limit) & Token

| Aspek | Nilai (default) | Konfigurasi |
|-------|-----------------|-------------|
| Login throttle | 5 / menit / IP | `throttle:pos-login` |
| API throttle | grup `pos-api` | `throttle:pos-api` |
| Masa berlaku token | 30 hari | `POS_TOKEN_TTL_DAYS` |
| Permission POS | `pos.view` | `POS_API_PERMISSION` |

Token dikirim di setiap request via `Authorization: Bearer <token>`. Logout mencabut token.

---

## 10. Catatan & Known Issues

### ⚠️ `GET /gudang` bisa `500` bila user punya `branch_id`

`MasterController::gudang()` memfilter `branch_id`, sedangkan tabel `master_gudang`
pada skema central **tidak memiliki kolom `branch_id`** → memicu *Server Error* saat
user login memiliki `branch_id`. Ini memblokir `POST /sesi/buka` (yang butuh `gudang_id`).

**Perbaikan yang disarankan** (guard seperti pola trait `BelongsToCompany`):

```php
// Modules/POS/app/Http/Controllers/Api/MasterController.php  → gudang()
->when($branchId && \Schema::hasColumn('master_gudang', 'branch_id'),
       fn ($w) => $w->where(fn ($s) => $s->where('branch_id', $branchId)->orWhereNull('branch_id')))
```

Alternatif cepat untuk demo (tanpa deploy ulang): kosongkan `branch_id` user demo
(single-branch aman). Perbaikan permanen memerlukan build & redeploy image.

### Catatan lain

- `gambar` produk saat ini dilayani dengan `Content-Type: application/octet-stream`
  (bukan `image/png`). Flutter `Image.network` tetap merender via byte — tidak
  memblokir, hanya kosmetik server.
- Data demo di-seed **idempoten** (aman dijalankan ulang) dan terisolasi pada
  perusahaan uji "TES POS".

---

## 11. Dokumentasi Interaktif (Swagger / OpenAPI)

| Bentuk | URL | Untuk |
|--------|-----|-------|
| **Swagger UI** | https://tatreport.com/api/pos/docs | Coba endpoint langsung dari browser |
| **Spesifikasi OpenAPI 3.0 (YAML)** | https://tatreport.com/api/pos/v1/openapi.yaml | Import ke Postman / Swagger Editor |

Diaktifkan via `POS_API_DOCS=true`. Sumber di repo:
[Modules/POS/resources/docs/pos-openapi.yaml](../Modules/POS/resources/docs/pos-openapi.yaml).

Rute sumber kebenaran endpoint: [Modules/POS/routes/api.php](../Modules/POS/routes/api.php).

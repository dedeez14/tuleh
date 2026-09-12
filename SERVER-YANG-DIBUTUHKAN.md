# Yang dibutuhkan dari server MOVERA (tatreport.com)

Daftar perubahan sisi server yang menunggu, diurutkan dari yang paling
berdampak. Ditulis agar bisa dipakai **langsung sebagai prompt** untuk orang
atau agen yang mengerjakan repo Laravel MOVERA — tiap bagian memuat kontrak
HTTP yang persis dipakai aplikasi hari ini, jadi tidak perlu menebak.

Konvensi yang sudah berlaku dan **tidak boleh berubah**:

- Prefix `/api/pos/v1`, envelope `{success, data, meta, message, errors}`.
- Semua `id` (toko, produk, transaksi, meja) adalah string terenkripsi ±267
  karakter — **bukan** angka. Aplikasi mengirimkannya kembali apa adanya.
- Semua teks yang sampai ke pengguna berbahasa Indonesia dan ditulis untuk
  kasir, bukan untuk programmer.
- Header `X-Tuleh-Version: <semver>` dikirim di setiap permintaan.
- Klien **fail-open**: endpoint yang belum ada (404) tidak boleh membuat
  aplikasi rusak, dan memang sudah ditangani begitu.

---

## 1. Idempotensi `client_ref` — PALING PENTING (menyangkut uang)

### Masalah nyata

Aplikasi punya mode offline: transaksi yang gagal terkirim disimpan di
perangkat lalu dikirim ulang saat internet kembali. Yang belum aman adalah
kasus **"server sudah menerima, jawabannya yang tidak sampai"** (sinyal putus
setelah request terkirim, timeout terima). Aplikasi tidak bisa membedakannya
dari "belum sampai sama sekali".

Karena server belum mengenal `client_ref`, aplikasi terpaksa:

- menandai baris itu **perlu ditinjau** dan menyuruh kasir memeriksa Riwayat
  sendiri sebelum mengirim ulang, dan
- untuk transaksi kasir, mencocokkan sendiri ke daftar transaksi hari itu
  (total + metode + waktu ±15 menit) — tebakan yang bisa salah bila ada dua
  transaksi kembar.

Kalau kasir salah menebak lalu mengirim ulang, **penjualan tercatat dua kali
dan stok terpotong dua kali**.

### Yang sudah dikirim aplikasi sekarang

Setiap permintaan tulis dari antrean offline membawa dua field tambahan di
badan JSON:

```jsonc
{
  "client_ref": "5f2c1a6e-8f3d-4b21-9a77-0c2f9d1e4b88",  // UUID v4, dibuat di perangkat
  "waktu_klien": "2026-09-09T14:05:33",                  // ISO-8601 waktu LOKAL kasir, detik penuh
  "...": "field asli endpoint yang bersangkutan"
}
```

Endpoint yang sudah mengirimkannya:

| Jenis | Endpoint |
|---|---|
| CHECKOUT | `POST /transaksi/checkout` |
| PENGELUARAN | `POST /pengeluaran` |
| STOK_MASUK | `POST /inventory/stok-masuk` |
| OPNAME | `POST /inventory/opname` |
| SESI_BUKA | `POST /sesi/buka` |
| BILL_BUKA | `POST /bills` |
| BILL_RONDE | `POST /bills/{id}/rounds` |
| BILL_BAYAR | `POST /bills/{id}/settle` |

Field ini **sudah dikirim hari ini** dan diabaikan server tanpa error, jadi
menambahkan dukungannya tidak memerlukan rilis aplikasi baru.

### Yang harus dilakukan server

1. Simpan `client_ref` pada baris yang dibuat, unik per **(pengguna, endpoint,
   client_ref)**. Gunakan unique index — jangan mengandalkan pengecekan
   "select dulu lalu insert" yang bisa balapan.
2. Bila `client_ref` yang sama datang lagi:
   - **jangan** membuat baris baru;
   - balas **200** (bukan 409) dengan `data` yang **sama persis** seperti
     jawaban pertama — khususnya `id` dan `nomor`;
   - tambahkan penanda di `meta`, mis. `{"idempoten": true}`, supaya aplikasi
     bisa memberi tahu kasir bahwa ini kiriman ulang, bukan transaksi baru.
3. Berlaku juga saat permintaan pertama gagal di tengah jalan: transaksi
   database harus atomis, sehingga `client_ref` hanya tersimpan bila barisnya
   benar-benar tercipta.
4. Simpan `waktu_klien` sebagai informasi (kapan kasir sebenarnya menekan
   bayar). Jangan dipakai sebagai waktu resmi transaksi kecuali memang
   diinginkan — jam perangkat kasir bisa salah.
5. **Uraikan `waktu_klien` sebelum disimpan, jangan diteruskan mentah ke kolom
   `datetime`.** Lihat catatan di bawah.

### Catatan lapangan: `client_created_at` menolak seluruh transaksi (12 Sep 2026)

Setelah kolom `client_created_at` aktif, checkout dari aplikasi Windows selalu
gagal:

```
SQLSTATE[22007]: Invalid datetime format: 1292 Incorrect datetime value:
'2026-09-12T07:25:40.635Z' for column 'client_created_at' at row 1
```

Sebabnya nilai `waktu_klien` disisipkan apa adanya ke kolom `datetime`; MySQL
menolak akhiran zona `Z`. Akibatnya **penjualan tidak bisa diselesaikan sama
sekali** — bukan sekadar kolom kosong.

Sisi aplikasi sudah diperbaiki (desktop 0.9.32 / Android 2.27.4): `waktu_klien`
kini selalu `YYYY-MM-DDTHH:MM:SS` waktu lokal kasir, tanpa milidetik dan tanpa
akhiran zona, dan baris antrean lama ikut dirapikan sebelum dikirim ulang.

Server tetap sebaiknya bertahan sendiri, karena APK lama yang sudah terpasang
di ponsel pelanggan masih akan mengirim format lain:

- uraikan nilainya (`Carbon::parse($v)`) lalu simpan hasilnya; nilai ber-`Z`
  artinya UTC dan perlu dikonversi ke zona toko;
- bila tidak bisa diuraikan, **simpan null** dan tetap proses transaksinya —
  kolom informasi tidak boleh menggagalkan penjualan;
- validasi `waktu_klien` sebagai `nullable|date` supaya kesalahannya muncul
  sebagai 422 yang jelas, bukan galat SQL mentah yang bocor ke layar kasir
  (pesan SQL lengkap berisi nama tabel & kolom sebaiknya tidak dikirim ke
  klien).

### Kenapa `id` dan `nomor` wajib ikut di jawaban ulang

Aplikasi memakai `data.id` dari jawaban untuk menyambung antrean berantai:
bon meja yang dibuka offline memakai rujukan sementara `lokal:<client_ref>` di
path, lalu diganti id server begitu baris induknya terkirim. Tanpa `id` pada
jawaban ulang, ronde dan pelunasan bon itu tidak bisa dikirim.

### Uji terima

- Kirim checkout yang sama dua kali dengan `client_ref` identik → hanya satu
  transaksi tercipta, jawaban kedua memuat `id`/`nomor` yang sama.
- Dua checkout dengan `client_ref` berbeda tetapi isi identik → dua transaksi
  (memang dua penjualan).
- Dua permintaan `client_ref` sama yang tiba **bersamaan** → tetap satu baris.

---

## 2. Kelola meja: `POST/PUT/DELETE /tables`

### Kebutuhan

Jumlah meja hari ini hanya bisa diatur lewat ERP tatreport. Pemilik warung
ingin menambah/mengubahnya langsung dari aplikasi kasir (desktop & Android).
Aplikasi sekarang **hanya membaca**: `GET /tables` dan `GET /bills`.

### Bentuk yang sudah dipakai aplikasi

`GET /tables` → `data: [{ id, nomor, kode }]`
`GET /bills` → `data: { tables: [{ id, nomor, kode, bill }] }`

`kode` dipakai untuk QR pesan-mandiri pelanggan (`/o/{kode}`), dicetak per meja.

### Endpoint yang diminta

```
POST   /tables            { "nomor": "7", "kode": "opsional" }
PUT    /tables/{id}       { "nomor": "7A", "kode": "opsional" }
DELETE /tables/{id}
```

Aturan:

1. `nomor` wajib, unik per toko, bebas huruf+angka (mis. "7", "A3", "VIP-1").
   Tolak 422 dengan pesan Indonesia bila bentrok.
2. `kode` (QR) dibuat server bila tidak dikirim. Harus acak, tidak mudah
   ditebak, dan **tidak berubah** saat meja di-rename — QR yang sudah
   tercetak dan tertempel di meja harus tetap berlaku.
3. `DELETE` **ditolak 409** bila meja itu punya bon berstatus BUKA, dengan
   pesan yang menyebut nomor bonnya. Meja yang pernah dipakai sebaiknya
   di-nonaktifkan (soft delete) daripada dihapus, agar riwayat lama tetap
   utuh.
4. Balas objek meja yang sama bentuknya dengan `GET /tables`, supaya aplikasi
   bisa langsung memperbarui daftarnya.
5. Hak akses: hanya peran pemilik/admin. Kasir biasa cukup membaca.

Bila ingin menambah banyak meja sekaligus (kasus "warung saya punya 12 meja"),
boleh disediakan `POST /tables/massal { "sampai": 12 }` yang membuat meja yang
belum ada saja — tetapi ini opsional, aplikasi bisa memanggil `POST /tables`
berulang.

---

## 3. `GET /app/versi` belum mengenal aplikasi Flutter

Aplikasi Android sekarang ada dua: yang lama (Capacitor, versi 0.9.x, satu
nomor dengan desktop) dan yang utama (Flutter, versi 2.x). Server hanya
mengenal jalur 0.9.x, sehingga aplikasi Flutter **selalu** mendapat jawaban
"tidak ada pembaruan" dan terpaksa membaca GitHub Releases sendiri.

Yang diminta: bedakan jalur rilis, mis. lewat parameter yang sudah dikirim
klien atau parameter baru:

```
GET /app/versi?versi=2.24.0&platform=android-flutter
GET /app/versi?versi=0.9.25&platform=android-legacy
GET /app/versi?versi=0.9.25&platform=windows
```

Jawaban tetap seperti sekarang (`wajib`, `update_tersedia`, `versi_terbaru`,
`versi_minimum`, `catatan`, url unduhan). Rinciannya ada di
[SERVER-AUTO-UPDATE.md](SERVER-AUTO-UPDATE.md).

Selama ini belum ada, aplikasi Flutter tetap aman (memakai GitHub Releases),
tetapi **hanya server yang boleh menyatakan pembaruan wajib** — jadi selama
jalur ini kosong, tidak ada cara memaksa update untuk aplikasi Flutter.

---

## 4. Konfirmasi `GET /laporan/penjualan-produk`

Aplikasi desktop sudah lama memakainya untuk kartu "Produk Terlaris", dan
sejak Android 2.21.0 aplikasi HP ikut memakainya. Saya tidak bisa memastikan
endpoint ini benar-benar hidup di produksi.

Yang dibutuhkan: konfirmasi endpoint ada, plus bentuk jawabannya. Aplikasi
menerima **dua bentuk** (keduanya sudah didukung):

```jsonc
"data": [ { "produk": "Kopi Susu", "qty_terjual": 120, "total_nilai": 2160000 } ]
// atau
"data": { "rows": [ { "produk": "...", "qty_terjual": 0, "total_nilai": 0 } ] }
```

Bila belum ada, balas 404 saja — aplikasi sudah menyembunyikan bagian itu
dengan rapi (sejak 2.21.1) alih-alih menampilkan kartu galat.

---

## 5. Validasi pembayaran kurang di sisi server

`POST /transaksi/checkout` menerima `dibayar` yang **lebih kecil** dari total
dan tetap membuat transaksi. Hal yang sama berlaku pada `POST
/bills/{id}/settle`. Aplikasi sudah menjaganya di sisi kasir (tombol Bayar
dikunci), tetapi penjagaan itu bisa dilewati oleh klien lain atau versi lama.

Diminta: tolak 422 bila `tipe_pembayaran` = TUNAI dan `dibayar < grand_total`,
dengan pesan Indonesia yang jelas. Untuk QRIS/TRANSFER, `dibayar` boleh
dianggap sama dengan total.

---

## 6. Bentuk laporan yang tidak konsisten (prioritas rendah)

`/laporan/*` kadang membalas `data` berupa list, kadang `data.rows`. Aplikasi
sudah toleran terhadap keduanya, jadi ini hanya kerapian. **Bila diseragamkan,
jangan hapus bentuk lama** — aplikasi versi lama masih beredar di HP kasir.

---

## 7. Masa coba Mode Demo (`/demo/*`)

Sudah ada dokumen terpisah: [KONTRAK-MASA-COBA.md](KONTRAK-MASA-COBA.md).
Statusnya menunggu keputusan pemilik soal kanal OTP (WhatsApp atau e-mail).
Aplikasi sudah memanggil endpoint ini dan fail-open pada 404.

---

## Cara menguji dengan aman

Server ini melayani toko sungguhan. Saat menguji endpoint tulis:

- pakai payload yang pasti ditolak validator (mis. `items: []`) bila hanya
  ingin memeriksa keberadaan endpoint; atau
- langsung batalkan transaksi uji lewat `POST /transaksi/{id}/batal`.
- Cloudflare memblokir User-Agent bawaan curl/Python (error 1010). Pakai
  User-Agent lain, mis. `Dart/3.10 (dart:io)`.

---

## Ringkas untuk ditempel sebagai prompt

> Kamu mengerjakan API MOVERA POS (Laravel, `https://tatreport.com`, prefix
> `/api/pos/v1`) yang dipakai aplikasi kasir Tuléh (Windows + Android).
> Kerjakan berurutan dari yang paling berdampak:
>
> 1. **Idempotensi `client_ref`** pada delapan endpoint tulis (checkout,
>    pengeluaran, stok-masuk, opname, sesi/buka, bills, bills/{id}/rounds,
>    bills/{id}/settle). Klien sudah mengirim `client_ref` (UUID v4) dan
>    `waktu_klien` (ISO-8601) di badan JSON. Kiriman ulang dengan
>    `client_ref` sama harus membalas 200 berisi `data` yang identik dengan
>    jawaban pertama (terutama `id` dan `nomor`), menambahkan
>    `meta.idempoten = true`, dan TIDAK membuat baris baru. Pakai unique
>    index per (pengguna, endpoint, client_ref) dan transaksi database yang
>    atomis. Ini mencegah penjualan tercatat dua kali saat sinyal putus
>    setelah request terkirim.
> 2. **CRUD meja**: `POST /tables`, `PUT /tables/{id}`, `DELETE /tables/{id}`
>    dengan bentuk objek sama seperti `GET /tables` (`{id, nomor, kode}`).
>    `nomor` unik per toko; `kode` QR dibuat server dan tidak berubah saat
>    meja di-rename; DELETE ditolak 409 bila meja punya bon BUKA (sebutkan
>    nomor bonnya); hanya pemilik/admin yang boleh mengubah.
> 3. **`GET /app/versi` mengenali jalur rilis** lewat parameter `platform`
>    (`windows`, `android-legacy`, `android-flutter`), karena aplikasi
>    Android Flutter memakai penomoran 2.x yang berbeda dari 0.9.x.
> 4. Konfirmasi `GET /laporan/penjualan-produk` hidup di produksi beserta
>    bentuk jawabannya.
> 5. Tolak 422 pada checkout/settle TUNAI bila `dibayar < grand_total`.
>
> Aturan yang tidak boleh dilanggar: envelope `{success, data, meta, message,
> errors}`; semua `id` tetap string terenkripsi; semua pesan galat berbahasa
> Indonesia dan ditulis untuk kasir; jangan mengubah bentuk jawaban lama
> karena aplikasi versi lama masih beredar; endpoint baru boleh 404 sampai
> siap (klien fail-open).

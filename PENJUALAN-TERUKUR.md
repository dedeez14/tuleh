# Penjualan terukur: per kilo & "beli sekian rupiah"

Desain untuk bidang usaha yang menjual berdasarkan **ukuran** (buah, sayur,
daging, beras, laundry kiloan, cat literan, kain meteran) — bukan per potong.
Kasir harus bisa melayani dua kalimat pelanggan yang sama-sama wajar:

- *"Mangga 2 kilo."* → kasir mengetik **berat**;
- *"Mangga dua puluh ribu."* → kasir mengetik **nominal**.

Dokumen ini menetapkan skema datanya, aturan pembulatan, alur layarnya, dan
apa yang berubah di desktop, Android, mesin demo, serta struk.

---

## Keadaan sekarang (sebelum perubahan)

| | Desktop (0.9.27) | Android (2.26.0) |
|---|---|---|
| Kuantitas pecahan | **Ya** — `satuan == 'kg'` membuka dialog berat | **Tidak** — `CartItem.qty` bertipe `int` |
| Beli per nominal | Tidak ada | Tidak ada |
| Satuan yang dikenali | hanya `kg` | — |

Server sudah menerima `kuantitas` pecahan (jalur laundry kiloan desktop dipakai
di produksi), dan `stok` juga pecahan. Jadi **tidak ada perubahan server yang
diperlukan** untuk fitur ini.

---

## Keputusan inti: berat yang dijual, nominal hanya cara mengetik

Ada dua kemungkinan sumber kebenaran satu baris keranjang:

| Pilihan | Konsekuensi |
|---|---|
| **A. Kuantitas yang benar** (dipilih) | Uang selalu = `kuantitas × harga`, cocok dengan hitungan server. Nominal yang diketik kasir diterjemahkan ke berat, lalu totalnya dihitung ulang dari berat itu. |
| B. Nominal yang benar | Perlu `subtotal` per baris di kontrak checkout (perubahan server), dan berat menjadi angka semu yang tidak bisa ditimbang. |

**Pilihan A** dipakai karena cocok dengan kenyataan di lapangan: pedagang
menimbang sampai mendekati nominal yang diminta, lalu menyebut hasilnya. Tidak
ada barang yang benar-benar seberat 0,7407 kg.

Contoh, mangga Rp 27.000/kg, pelanggan minta Rp 20.000:

```
nominal 20.000 ÷ 27.000  = 0,74074… kg
dibulatkan ke langkah timbangan (0,01 kg) → 0,74 kg
total yang ditagih = 0,74 × 27.000 = Rp 19.980
```

Layar menampilkan ketiganya sekaligus, sehingga kasir bisa bilang: *"0,74 kilo,
Rp 19.980"*. Tidak ada selisih tersembunyi antara yang tampil dan yang tercatat.

### Aturan pembulatan

1. **Kuantitas** dibulatkan ke `langkah` satuannya (lihat tabel di bawah),
   pembulatan **ke bawah** saat berasal dari nominal — supaya tagihan tidak
   pernah melebihi nominal yang diminta pelanggan.
2. **Uang** dibulatkan ke rupiah penuh (`round`), sama seperti seluruh aplikasi.
3. Bila hasil pembulatan kuantitas menjadi 0 (nominal lebih kecil dari satu
   langkah), baris ditolak dengan pesan yang menyebut minimum belanjanya.

---

## Skema data

### 1. Klasifikasi satuan (di klien, tanpa perubahan server)

Server hanya mengirim `satuan` (teks bebas). Klien menerjemahkannya:

```
satuan  → terukur?  langkah  contoh tampilan
kg         ya        0,01     0,74 kg
gram / gr  ya        10       250 gram
ons        ya        0,1      2,5 ons
liter / l  ya        0,01     1,5 liter
ml         ya        10       500 ml
meter / m  ya        0,1      2,5 meter
pcs/pack/… tidak     1        2 pcs
```

Satuan tak dikenal dianggap **tidak terukur** (aman: perilaku lama).

> Opsional untuk server nanti: field `dijual_per` (`SATUAN` | `UKURAN`) dan
> `langkah` per produk, supaya pemilik bisa menentukan sendiri lewat ERP tanpa
> bergantung pada ejaan satuan. Klien harus tetap memakai tabel di atas sebagai
> cadangan.

### 2. Baris keranjang

```
CartItem {
  produk
  qty: double        // BERAT/UKURAN yang dijual — sumber kebenaran
  caraInput: enum { satuan, berat, nominal }   // hanya untuk tampilan & audit
  nominalDiminta: double?  // yang diketik kasir saat caraInput == nominal
}
```

`nominalDiminta` **tidak dikirim ke server** dan tidak memengaruhi uang; ia
hanya dipakai untuk menampilkan *"diminta Rp 20.000"* di keranjang dan struk
bila berbeda dari total baris, supaya kasir dan pelanggan sama-sama paham.

### 3. Yang dikirim ke server (tidak berubah)

```jsonc
{ "id_produk": "...", "kuantitas": 0.74, "harga": 27000, "diskon_persen": 0 }
```

Server tetap menghitung `subtotal = harga × kuantitas × (1 − diskon)`.

### 4. Penyimpanan lokal

- **Antrean offline**: `kuantitas` sudah pecahan; delta stok sudah `double`.
- **Parkir keranjang**: `qty` disimpan sebagai angka (JSON `num`) — pembaca
  harus menerima `2` maupun `0.74` agar keranjang lama tetap terbaca.
- **Struk lokal**: `StrukBaris.kuantitas` sudah `num`.

---

## Alur layar

### Menambah barang terukur

Mengetuk produk terukur **tidak** langsung menambah 1, melainkan membuka satu
lembar dengan dua cara isi:

```
┌ Mangga Harum Manis ───────────── Rp 27.000 / kg ┐
│  [ Berat ]  [ Nominal ]        ← dua tab        │
│                                                  │
│  Berat:  [ 0,74 ] kg                             │
│  cepat:  ½kg  1kg  2kg  5kg                      │
│                                                  │
│  0,74 kg × Rp 27.000 = Rp 19.980                 │
│                                   [ Tambah ]     │
└──────────────────────────────────────────────────┘
```

Tab **Nominal** menukar kolom isian menjadi rupiah, dengan pintasan
5.000 / 10.000 / 20.000 / 50.000, dan barisnya menampilkan:

```
Rp 20.000 → 0,74 kg × Rp 27.000 = Rp 19.980
```

### Mengubah baris di keranjang

Untuk barang terukur, tombol +/− diganti tombol **"Ubah"** yang membuka lembar
yang sama (nilai awal = isi baris sekarang). Menaikkan "1 pcs" tidak masuk akal
untuk barang yang ditimbang.

### Struk

```
Mangga Harum Manis
  0,74 kg x 27.000            19.980
```

Bila baris berasal dari nominal dan hasilnya berbeda, struk menambah keterangan
kecil: `(diminta Rp 20.000)`.

---

## Batas & penjagaan

| Keadaan | Perlakuan |
|---|---|
| Harga 0 / kosong | Tab nominal dimatikan (tidak bisa membagi) dengan penjelasan |
| Nominal < satu langkah | Ditolak: *"Minimal belanja untuk Mangga adalah Rp 270 (0,01 kg)."* |
| Stok kurang dari berat yang diminta | Sama seperti sekarang: ditolak dengan menyebut sisa stok (stok pecahan) |
| Diskon transaksi | Tetap berlaku sebagai persen per baris — tidak bertabrakan dengan pembulatan berat |
| Barang tak terukur | Perilaku lama: ketuk = +1, tombol +/− tetap |

---

## Yang berubah di kode

### Bersama
- `satuan_terukur` (Dart) / `satuan-terukur.js` (JS): tabel satuan → langkah,
  `apakahTerukur()`, `bulatkanKuantitas()`, `kuantitasDariNominal()`,
  `labelKuantitas()`. **Logika murni, diuji tanpa UI.**

### Android (perubahan terbesar)
- `CartItem.qty`: `int` → `double` (+ `caraInput`, `nominalDiminta`).
  Ikut berubah: `cart_controller`, `keranjang_daftar_item` (stepper → tombol
  Ubah untuk barang terukur), `cart_sheet`, `checkout_repository`,
  `parkir_store` (baca `num`), `kasir_screen`, `parkir_sheet`.
- Lembar baru `lembar_ukuran.dart` (dua tab).

### Desktop
- Ganti `satuan === 'kg'` dengan `apakahTerukur(satuan)`.
- Dialog berat yang sudah ada ditambah tab **Nominal** + pintasan.
- Baris keranjang: tombol Ubah untuk barang terukur.

### Mesin demo (dua aplikasi)
- Tambah beberapa produk terukur di katalog demo (buah/sayur per kg) supaya
  fitur ini bisa dicoba tanpa akun.

### Uji
- Fungsi murni: pembulatan ke langkah, nominal → kuantitas (termasuk kasus
  pembagian tak bulat), penolakan di bawah minimum, harga 0.
- Alur: ketuk produk kg → lembar terbuka; isi nominal → keranjang berisi berat
  yang benar dan total yang cocok; struk memuat "0,74 kg x 27.000".
- Regresi: barang tak terukur tetap +1 dan stepper-nya utuh.

---

## Yang sengaja TIDAK dikerjakan sekarang

- **Timbangan digital tersambung** (serial/USB/Bluetooth). Desainnya sudah siap
  menerimanya: satu tempat yang mengisi kolom berat. Ditunda karena butuh
  perangkat sungguhan untuk diuji.
- **Harga bertingkat** (mis. di atas 5 kg lebih murah) — kebijakan harga milik
  ERP, bukan kasir.
- **`dijual_per` di server** — berguna, tetapi klien sudah bisa jalan tanpa itu.

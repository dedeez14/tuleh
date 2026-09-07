# Catatan rilis — Tuléh Android (Flutter)

Bagian `## X.Y.Z` teratas yang cocok dengan `version:` di pubspec.yaml dipakai
sebagai isi Release GitHub (workflow flutter-release.yml), dan empat baris
pertamanya tampil di banner pembaruan dalam aplikasi. Tulis untuk kasir, bukan
untuk programmer.

## 2.13.0

- Tablet (layar ≥ 720 dp) kini tampil ala desktop: kasir dua panel (katalog grid di kiri, keranjang menetap di kanan dengan langkah bayar di panel yang sama), riwayat master-detail (daftar di kiri, struk di kanan dengan Bagikan/Cetak ulang), beranda dua kolom, dan daftar Produk/Stok/Pengeluaran/Pelanggan/Sesi/Pengaturan/Laporan dibatasi lebarnya agar nyaman dibaca. Ponsel tetap memakai tata letak sebelumnya.
- Hasil transaksi, pilih pelanggan, dan menu Lainnya tampil sebagai dialog di tablet, bukan lembar selebar layar.
- Perbaikan: label saran nominal uang (Uang pas, Rp 20.000, …) sebelumnya tidak terlihat karena warna teks chip tidak ditetapkan.

## 2.12.0

- Kasir lebih ringkas: harga, satuan, dan stok dalam satu baris, tombol tambah bulat; sekitar delapan produk terlihat sekali pandang (sebelumnya lima). Pengatur jumlah tetap muncul untuk item yang sudah di keranjang.
- Beranda menyapa sesuai waktu (pagi/siang/sore/malam).
- Detail transaksi punya tombol Bagikan dan Cetak ulang yang jelas di bawah struk.
- Daftar produk tidak lagi tertutup tombol Tambah Produk di baris terakhir.

## 2.11.0

- Keranjang: pilih pelanggan (cari nama/telepon, tambah cepat), diskon transaksi dalam persen, dan catatan. Total di kasir dan lembar bayar sudah setelah diskon; dikirim ke server dengan kontrak yang sama seperti desktop (diskon per item, id pelanggan, catatan).
- Struk cetak, teks bagikan, dan lembar hasil menampilkan pelanggan, subtotal, dan potongan diskon; cetak ulang dari Riwayat ikut memuatnya.
- Mode Demo menghitung diskon dan pelanggan seperti server.

## 2.10.0

- Cetak ulang dan Bagikan struk dari detail Riwayat; tombol Bagikan struk (WhatsApp/pesan/salin, teks 32 kolom seperti struk thermal) di lembar hasil transaksi.
- Pengaturan → Tampilan: ikuti sistem, terang, atau gelap (tersimpan di perangkat).
- Beranda: aksi cepat Pengeluaran; layar Meja menampilkan keadaan kosong yang lebih jelas.
- Mode Demo dibatasi: struk bertanda "MODE DEMO — bukan bukti pembayaran" (cetak, pratinjau, teks) dan paling banyak 20 transaksi per hari yang dibuat pengguna.

## 2.9.0

- Mode offline tahap ketiga: sesi kasir bisa dibuka saat internet mati. Sesi tercatat di ponsel, dikirim ke server lebih dulu sebelum transaksi yang dibuat di dalamnya, dan menutup sesi ditahan sampai semua data terkirim agar rekap kas benar.
- Bon meja saat offline: buka bon, tambah pesanan ke dapur, dan bayar bon disimpan di ponsel lalu dikirim berurutan begitu online. Peta meja dan detail bon langsung menampilkan pesanan yang belum terkirim (tanda "Offline" di meja).
- Sinkronisasi: baris yang bergantung pada bon lain dijelaskan sebabnya bila perlu ditinjau; Kirim ulang bon induk otomatis melanjutkan pesanan di bawahnya; Batalkan bon induk ikut membatalkan pesanannya.

## 2.8.0

- Mode offline tahap kedua: transaksi, pengeluaran, dan stok masuk saat internet mati disimpan di ponsel lalu dikirim otomatis berurutan begitu server terjangkau. Struk offline memakai nomor sementara L-…, stok di katalog langsung berkurang, dan riwayat menampilkan transaksi yang belum terkirim dengan tanda.
- Baru: Pengaturan → Sinkronisasi menampilkan antrean, tombol Sinkron sekarang, dan pilihan Kirim ulang / Batalkan untuk transaksi yang perlu ditinjau (server tidak menjawab setelah data dikirim, atau server menolak).
- Keluar akun ditahan bila masih ada transaksi yang belum terkirim, agar penjualan tidak hilang.
- Pembaruan aplikasi: pemasang terbuka otomatis begitu unduhan selesai. Bila unduhan selesai saat aplikasi di latar belakang, pemasang dibuka otomatis saat aplikasi dibuka kembali dan ada notifikasi "siap dipasang" yang bisa diketuk. Tidak perlu lagi mencari berkas unduhan.

## 2.7.0

- Mode offline tahap pertama: data yang pernah dimuat (produk, pelanggan, riwayat, laporan, pengaturan, sesi, meja) tetap bisa dilihat saat internet mati. Pita "Offline · menampilkan data terakhir HH:MM" tampil dengan tombol Coba lagi, dan data dimuat ulang otomatis begitu server terjangkau. Transaksi baru masih membutuhkan koneksi (tahap berikutnya: antrean kirim).

## 2.6.1

- Daftar toko selalu diambil ulang dari server saat berganti akun. Sejak 5 September server hanya memberi toko yang ditugaskan ke pengguna; daftar dari akun sebelumnya tidak lagi tersisa di pemilih toko.

## 2.6.0

- Masa coba demo kini tercatat di server per perangkat dan, bila server memintanya, per nomor WhatsApp atau email lewat kode verifikasi. Menghapus aplikasi atau mereset ponsel tidak mengulang masa coba. Aktif otomatis setelah server MOVERA memasang endpointnya; sebelum itu perilaku sama dengan versi 2.5.0.

## 2.5.0

- Mode Demo kini masa coba 7 hari sejak pertama dibuka di ponsel ini, dihitung dengan waktu server (mengubah jam ponsel tidak berpengaruh). Lencana DEMO menampilkan sisa hari. Setelah berakhir, aplikasi terkunci sampai masuk dengan akun berlangganan. Membuka demo pertama kali perlu koneksi internet.

## 2.4.1

- Perbaikan: lembar "Pilih toko" tertutup bilah navigasi bawah dan tidak bisa digulir, sehingga toko di bawah tidak bisa dipilih. Lembar kini tampil di atas bilah dan bisa digulir; berlaku juga untuk keranjang dan menu Lainnya.

## 2.4.0

- Baru: Notifikasi pesanan meja. Nyalakan di Pengaturan; aplikasi memantau pesanan dan permintaan bayar dari QR meja di latar belakang, lalu berbunyi walau aplikasi ditutup.
- Lebih cepat: beranda tidak lagi membaca Keystore dua kali untuk setiap permintaan ke server, penyebab "Memuat toko…" terasa lama di banyak ponsel Android 10.
- Kepala dasbor menampilkan alasan dan tombol ulang bila daftar toko gagal dimuat, bukan "Memuat toko…" tanpa akhir.
- Pola latar bermerek di layar masuk dan dasbor.
- Kasir menampilkan foto produk dan harga promo (harga normal dicoret) sesuai pengaturan server.
- Katalog dengan lebih dari 50 produk kini dimuat seluruhnya; layar Produk menampilkan produk berstok 0 agar bisa direstok.
- Perbaikan tanggal grafik penjualan yang mundur satu hari, dan jam "00:00" palsu di Riwayat.

## 2.3.0

- Kolom uang berformat rupiah saat diketik: 50000 tampil 50.000 (uang diterima, kas awal/akhir sesi, pengeluaran, harga produk).
- Bayar tunai terkunci sampai uang diterima diisi dan cukup; kembalian tampil sebelum menekan Bayar.
- Saat QRIS: gambar QRIS statis toko tampil beserta total. Saat TRANSFER: daftar rekening toko dengan tombol salin. Keduanya dari pengaturan yang diisi di desktop.
- Logo struk yang diatur di desktop tampil di lembar hasil dan ikut dicetak ke printer thermal.
- Perbaikan: "items.0.id_produk harus bilangan bulat" saat bayar setelah berpindah dari Mode Demo ke akun sungguhan. Keranjang kini dikosongkan saat ganti toko atau akun.

## 2.2.1

- Perbaikan: tombol "Unduh" pembaruan gagal dengan "URL unduhan tidak valid / host tidak diizinkan" karena aplikasi hanya mengizinkan unduhan dari server, padahal versi baru diterbitkan di GitHub. Versi ini yang terakhir perlu dipasang manual; berikutnya cukup tekan Unduh.

## 2.2.0

- Logo Tuléh (notepad + pensil) kembali dipakai untuk ikon aplikasi, splash, dan layar masuk — sama seperti desktop.
- Splash mengikuti gaya desktop: latar putih-mint dengan logo, tanpa kilatan warna gelap.
- Ikon aplikasi dikalibrasi agar tidak terpotong di launcher berbentuk lingkaran.

## 2.1.0

- Pembaruan versi kini ditemukan otomatis dari GitHub Releases bila server belum mengenal versi Flutter.
- Riwayat dikelompokkan per hari dengan subtotal dan jam transaksi.
- Produk jasa berlencana "Jasa", bukan "Stok 0".

## 2.0.0

- Navigasi bawah Material 3: Beranda, Kasir, tab sesuai bidang usaha, Laporan; menu lain di lembar "Lainnya".
- Beranda menjadi dasbor: status sesi, penjualan hari ini, transaksi terakhir.
- Perbaikan tata letak di ponsel sempit dan tablet.

# Catatan rilis — Tuléh Android (Flutter)

Bagian `## X.Y.Z` teratas yang cocok dengan `version:` di pubspec.yaml dipakai
sebagai isi Release GitHub (workflow flutter-release.yml), dan empat baris
pertamanya tampil di banner pembaruan dalam aplikasi. Tulis untuk kasir, bukan
untuk programmer.

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

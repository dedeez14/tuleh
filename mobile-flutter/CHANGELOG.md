# Catatan rilis — Tuléh Android (Flutter)

Bagian `## X.Y.Z` teratas yang cocok dengan `version:` di pubspec.yaml dipakai
sebagai isi Release GitHub (workflow flutter-release.yml), dan empat baris
pertamanya tampil di banner pembaruan dalam aplikasi. Tulis untuk kasir, bukan
untuk programmer.

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

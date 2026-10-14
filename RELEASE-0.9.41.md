# Tuléh 0.9.41 / Android Flutter 2.34.0

Perbaikan sinkronisasi yang sebelumnya belum dirilis kini disertakan:

- Transaksi tertunda tetap milik toko dan akun pembuatnya walaupun kasir berpindah saat permintaan berjalan.
- Pengiriman ulang mempertahankan identitas transaksi dan hasil sinkronisasi yang sudah diterima.
- Refund/pembatalan offline dan rujukan transaksi lokal diperbaiki; hak akses tetap berlaku.
- Tutup sesi ditahan ketika masih ada transaksi yang perlu disinkronkan.
- Batch v2 hanya digunakan jika server menyatakan dukungannya. Tanpa dukungan tersebut, pengiriman per transaksi tetap digunakan.

## Pemeriksaan rilis

Tes Node dan Go berjalan setiap push, termasuk ketika nomor versi tidak berubah.
Installer Windows harus berhasil dipasang pada runner bersih, membuka Mode Demo,
menyelesaikan boot renderer, dan menjalankan gateway dengan versi yang sama.
Pengujian memakai profil sementara dengan upstream `.invalid`, tanpa token dan data pelanggan.
Laporan dan screenshot tersimpan sebagai artifact `desktop-install-smoke`.
APK pelanggan wajib ditandatangani keystore rilis; tidak ada fallback APK debug.
Tag rilis menunjuk tepat ke commit yang diuji, bukan HEAD yang mungkin berubah selama build.

## Pembaruan pelanggan

Selesaikan sinkronisasi antrean sebelum memperbarui. Pasang pembaruan di atas aplikasi lama;
jangan menghapus data aplikasi atau mencopot aplikasi yang masih mempunyai antrean.
Versi minimum server tidak dinaikkan otomatis oleh perubahan ini.
Nomor versi desktop/Capacitor dan Flutter berbeda dan memakai feed platform masing-masing.

Tes otomatis dan smoke installer belum menggantikan uji printer fisik, perangkat Android,
dan simulasi gangguan jaringan dengan backend staging sebelum rollout luas.

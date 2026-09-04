/// Pengaturan pembayaran toko (`GET /pengaturan/pembayaran`) — yang diatur
/// pemilik di desktop (Pengaturan → Pembayaran) dan ditunjukkan kasir ke
/// pelanggan saat metode QRIS/TRANSFER dipilih.
class PengaturanPembayaran {
  const PengaturanPembayaran({
    this.qrStatis,
    this.bank = const [],
    this.midtransAktif = false,
  });

  /// URL gambar QRIS statis merchant; null bila belum diunggah.
  final String? qrStatis;
  final List<RekeningBank> bank;
  final bool midtransAktif;

  static const kosong = PengaturanPembayaran();
}

class RekeningBank {
  const RekeningBank({
    required this.bank,
    required this.rekening,
    required this.atasNama,
  });

  final String bank;
  final String rekening;
  final String atasNama;
}

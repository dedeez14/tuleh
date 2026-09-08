/// Baris "produk terlaris" (`/laporan/penjualan-produk`).
///
/// Server mengembalikan nama produk apa adanya (bukan id), jadi entitas ini
/// sengaja tanpa id — dipakai untuk peringkat, bukan untuk menautkan katalog.
class PenjualanProduk {
  const PenjualanProduk({
    required this.produk,
    required this.qtyTerjual,
    required this.totalNilai,
  });

  final String produk;
  final double qtyTerjual;
  final double totalNilai;
}

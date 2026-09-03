/// Baris stok produk (dari GET /laporan/stok).
class StokItem {
  const StokItem({
    required this.id,
    required this.kode,
    required this.produk,
    required this.stok,
  });

  final String id;
  final String kode;
  final String produk;
  final double stok;

  bool get habis => stok <= 0;
  bool menipis(int ambang) => stok > 0 && stok <= ambang;
  bool perluRestok(int ambang) => stok <= ambang;
}

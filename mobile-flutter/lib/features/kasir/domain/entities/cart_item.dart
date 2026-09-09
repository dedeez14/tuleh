import '../../../../core/utils/satuan_terukur.dart';
import '../../../products/domain/entities/product.dart';

/// Cara kasir mengisi baris ini — hanya untuk tampilan; yang dikirim ke server
/// selalu [CartItem.qty].
enum CaraInput {
  /// Barang hitungan biasa (ketuk = +1).
  satuan,

  /// Barang terukur, kasir mengetik berat/ukurannya.
  ukuran,

  /// Barang terukur, kasir mengetik rupiah dan ukurannya dihitung dari situ.
  nominal,
}

/// Baris keranjang — produk + kuantitas. Imutable.
///
/// [qty] adalah UKURAN yang benar-benar dijual (0,74 kg), bukan sekadar
/// pencacah. Uang selalu `qty × harga`, sehingga cocok dengan hitungan server.
/// Lihat PENJUALAN-TERUKUR.md.
class CartItem {
  const CartItem({
    required this.product,
    required this.qty,
    this.cara = CaraInput.satuan,
    this.nominalDiminta,
  });

  final Product product;
  final double qty;
  final CaraInput cara;

  /// Rupiah yang diminta pelanggan saat [cara] == nominal. Tidak dikirim ke
  /// server; dipakai menampilkan "diminta Rp 20.000" bila hasilnya berbeda.
  final double? nominalDiminta;

  /// Uang baris ini — dibulatkan ke rupiah penuh.
  double get subtotal => totalBaris(qty, product.harga);

  bool get terukur => apakahTerukur(product.satuan);

  /// "0,74 kg" untuk barang terukur, "2" untuk barang hitungan.
  String get labelQty => terukur ? '${fmtQtyRingkas(qty)} ${product.satuan}' : fmtQtyRingkas(qty);

  CartItem copyWith({double? qty, CaraInput? cara, double? nominalDiminta}) => CartItem(
    product: product,
    qty: qty ?? this.qty,
    cara: cara ?? this.cara,
    nominalDiminta: nominalDiminta ?? this.nominalDiminta,
  );
}

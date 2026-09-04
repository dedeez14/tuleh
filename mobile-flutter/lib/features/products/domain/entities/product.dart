import 'package:freezed_annotation/freezed_annotation.dart';

part 'product.freezed.dart';

/// Entitas produk katalog. `harga` = harga yang DITAGIH kasir: harga promo bila
/// promo sedang aktif (server: `harga_efektif`), selain itu harga jual.
@freezed
abstract class Product with _$Product {
  const factory Product({
    required String id,
    required String nama,
    required double harga,
    String? tipe, // PRODUK | JASA
    double? hargaBeli,
    String? satuan,
    String? kategori,
    String? barcode,
    double? stok,
    /// Harga jual normal saat [promo] aktif (untuk dicoret di kartu).
    double? hargaNormal,
    @Default(false) bool promo,
    /// URL foto produk (server: `gambar`); null = tanpa foto.
    String? gambar,
  }) = _Product;
}

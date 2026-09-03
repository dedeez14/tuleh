import 'package:freezed_annotation/freezed_annotation.dart';

part 'product.freezed.dart';

/// Entitas produk katalog. `harga` = harga jual.
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
  }) = _Product;
}

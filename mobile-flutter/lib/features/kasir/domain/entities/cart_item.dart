import '../../../products/domain/entities/product.dart';

/// Baris keranjang — produk + kuantitas. Imutable.
class CartItem {
  const CartItem({required this.product, required this.qty});

  final Product product;
  final int qty;

  double get subtotal => product.harga * qty;

  CartItem copyWith({int? qty}) =>
      CartItem(product: product, qty: qty ?? this.qty);
}

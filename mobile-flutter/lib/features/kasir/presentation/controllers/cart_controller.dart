import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../products/domain/entities/product.dart';
import '../../../toko/presentation/providers/toko_providers.dart';
import '../../domain/entities/cart_item.dart';

/// Keranjang belanja (state lokal, imutable). Sumber kebenaran transaksi kasir.
///
/// Keranjang HANYA sah untuk toko & akun tempat item ditambahkan. Berganti
/// toko atau akun (termasuk keluar dari Mode Demo lalu masuk akun sungguhan)
/// mengosongkannya. Kasus nyata: item demo (id "MIN-003") tertinggal di
/// keranjang lalu dibayar ke server sungguhan → "items.0.id_produk harus
/// bilangan bulat".
class CartController extends Notifier<List<CartItem>> {
  @override
  List<CartItem> build() {
    ref.listen<AsyncValue<String?>>(activeTokoIdProvider, (prev, next) {
      final sebelum = prev?.valueOrNull;
      final sesudah = next.valueOrNull;
      if (prev != null && sebelum != sesudah) state = const [];
    });
    ref.listen(authControllerProvider, (prev, next) {
      final sebelum = prev?.valueOrNull?.id;
      final sesudah = next.valueOrNull?.id;
      if (prev != null && sebelum != sesudah) state = const [];
    });
    return const [];
  }

  void add(Product p) {
    final idx = state.indexWhere((e) => e.product.id == p.id);
    if (idx >= 0) {
      state = [
        for (var i = 0; i < state.length; i++)
          if (i == idx) state[i].copyWith(qty: state[i].qty + 1) else state[i],
      ];
    } else {
      state = [...state, CartItem(product: p, qty: 1)];
    }
  }

  void setQty(String productId, int qty) {
    if (qty <= 0) {
      remove(productId);
      return;
    }
    state = [
      for (final e in state)
        if (e.product.id == productId) e.copyWith(qty: qty) else e,
    ];
  }

  void remove(String productId) =>
      state = [for (final e in state) if (e.product.id != productId) e];

  void clear() => state = const [];
}

final cartControllerProvider =
    NotifierProvider<CartController, List<CartItem>>(CartController.new);

/// Total nilai keranjang (turunan — tidak disimpan ganda).
final cartTotalProvider = Provider<double>((ref) {
  return ref.watch(cartControllerProvider).fold<double>(0, (s, e) => s + e.subtotal);
});

/// Jumlah item (kuantitas) di keranjang.
final cartCountProvider = Provider<int>((ref) {
  return ref.watch(cartControllerProvider).fold<int>(0, (s, e) => s + e.qty);
});

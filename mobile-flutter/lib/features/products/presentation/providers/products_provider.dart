import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/offline/pengurai.dart';
import '../../../toko/presentation/providers/toko_providers.dart';
import '../../data/datasources/product_remote_datasource.dart';
import '../../data/repositories/product_repository_impl.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/product_repository.dart';

final productRepositoryProvider = Provider<ProductRepository>(
  (ref) => ProductRepositoryImpl(ProductRemoteDataSource(ref.watch(dioProvider))),
);

/// Kata kunci pencarian katalog (diikat ke kolom cari Kasir).
final productQueryProvider = StateProvider<String>((ref) => '');

/// Katalog KASIR toko aktif (tanpa produk berstok 0, seperti desktop).
/// Dependensi ke [activeTokoIdProvider] agar otomatis dimuat ulang saat toko
/// berganti; ke query untuk pencarian.
final productsProvider = FutureProvider<List<Product>>((ref) async {
  final tokoId = ref.watch(activeTokoIdProvider).valueOrNull; // refetch saat toko berubah
  final query = ref.watch(productQueryProvider);
  final result = await ref.watch(productRepositoryProvider).list(query: query);
  final produk = result.when(ok: (v) => v, err: (e) => throw e);
  return terapkanDeltaStok(produk, await _deltaTertunda(ref, tokoId));
});

/// Stok tampil = stok server + delta transaksi yang masih menunggu dikirim
/// (offline). Setelah antrean kosong dan katalog ditarik ulang, delta hilang.
List<Product> terapkanDeltaStok(List<Product> produk, Map<String, double> delta) {
  if (delta.isEmpty) return produk;
  return [
    for (final p in produk)
      p.stok != null && delta.containsKey(p.id)
          ? p.copyWith(stok: p.stok! + delta[p.id]!)
          : p,
  ];
}

Future<Map<String, double>> _deltaTertunda(Ref ref, String? tokoId) async {
  ref.watch(antreanVersiProvider);
  try {
    return await ref.watch(antreanStoreProvider).deltaStokTertunda(tokoId: tokoId);
  } catch (_) {
    return const {};
  }
}

/// Katalog KELOLA (layar Produk): termasuk produk berstok 0 agar pemilik bisa
/// melihat dan merestoknya — tanpa ini produk habis "menghilang" dari aplikasi.
final produkKelolaProvider = FutureProvider<List<Product>>((ref) async {
  final tokoId = ref.watch(activeTokoIdProvider).valueOrNull;
  final query = ref.watch(productQueryProvider);
  final result = await ref
      .watch(productRepositoryProvider)
      .list(query: query, includeHabis: true);
  final produk = result.when(ok: (v) => v, err: (e) => throw e);
  return terapkanDeltaStok(produk, await _deltaTertunda(ref, tokoId));
});

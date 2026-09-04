import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
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
  ref.watch(activeTokoIdProvider); // refetch saat toko berubah
  final query = ref.watch(productQueryProvider);
  final result = await ref.watch(productRepositoryProvider).list(query: query);
  return result.when(ok: (v) => v, err: (e) => throw e);
});

/// Katalog KELOLA (layar Produk): termasuk produk berstok 0 agar pemilik bisa
/// melihat dan merestoknya — tanpa ini produk habis "menghilang" dari aplikasi.
final produkKelolaProvider = FutureProvider<List<Product>>((ref) async {
  ref.watch(activeTokoIdProvider);
  final query = ref.watch(productQueryProvider);
  final result = await ref
      .watch(productRepositoryProvider)
      .list(query: query, includeHabis: true);
  return result.when(ok: (v) => v, err: (e) => throw e);
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../data/datasources/toko_remote_datasource.dart';
import '../../data/repositories/toko_repository_impl.dart';
import '../../domain/entities/toko.dart';
import '../../domain/repositories/toko_repository.dart';

final tokoRepositoryProvider = Provider<TokoRepository>(
  (ref) => TokoRepositoryImpl(TokoRemoteDataSource(ref.watch(dioProvider))),
);

/// Daftar toko tenant (dari server).
final tokoListProvider = FutureProvider<List<Toko>>((ref) async {
  final result = await ref.watch(tokoRepositoryProvider).list();
  return result.when(ok: (v) => v, err: (e) => throw e);
});

/// Toko aktif (id) — sumber kebenaran di secure storage; dipakai interceptor
/// Dio (toko_id) sehingga data (produk, dll.) otomatis ter-scope toko.
class ActiveTokoNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() => ref.watch(secureStorageProvider).readActiveTokoId();

  Future<void> select(String id) async {
    await ref.read(secureStorageProvider).writeActiveTokoId(id);
    state = AsyncData(id);
  }
}

final activeTokoIdProvider =
    AsyncNotifierProvider<ActiveTokoNotifier, String?>(ActiveTokoNotifier.new);

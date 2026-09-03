import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../../toko/presentation/providers/toko_providers.dart';
import '../../data/datasources/stok_remote_datasource.dart';
import '../../data/repositories/stok_repository_impl.dart';
import '../../domain/entities/stok_item.dart';
import '../../domain/repositories/stok_repository.dart';

final stokRepositoryProvider = Provider<StokRepository>(
  (ref) => StokRepositoryImpl(StokRemoteDataSource(ref.watch(dioProvider))),
);

/// Daftar stok toko aktif, diurutkan stok terendah dulu (paling perlu perhatian).
final stokListProvider = FutureProvider<List<StokItem>>((ref) async {
  ref.watch(activeTokoIdProvider);
  final r = await ref.watch(stokRepositoryProvider).list();
  final list = r.when(ok: (v) => v, err: (e) => throw e);
  final sorted = [...list]..sort((a, b) => a.stok.compareTo(b.stok));
  return sorted;
});

/// Ambang "perlu restok" (persist di secure storage). Default 5.
class RestokAmbangNotifier extends AsyncNotifier<int> {
  @override
  Future<int> build() => ref.watch(secureStorageProvider).readRestokAmbang();

  Future<void> set(int value) async {
    final v = value < 0 ? 0 : value;
    await ref.read(secureStorageProvider).writeRestokAmbang(v);
    state = AsyncData(v);
  }
}

final restokAmbangProvider =
    AsyncNotifierProvider<RestokAmbangNotifier, int>(RestokAmbangNotifier.new);

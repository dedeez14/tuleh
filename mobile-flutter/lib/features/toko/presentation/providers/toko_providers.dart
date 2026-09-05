import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../data/datasources/toko_remote_datasource.dart';
import '../../data/repositories/toko_repository_impl.dart';
import '../../domain/entities/toko.dart';
import '../../domain/entities/toko_manifest.dart';
import '../../domain/repositories/toko_repository.dart';

final tokoRepositoryProvider = Provider<TokoRepository>(
  (ref) => TokoRepositoryImpl(TokoRemoteDataSource(ref.watch(dioProvider))),
);

/// Daftar toko yang menjadi hak pengguna (dari server, tidak pernah disimpan
/// di perangkat). Server menyaringnya per pengguna (users.pos_toko_id), jadi
/// daftar WAJIB diambil ulang setiap kali pengguna berganti — tanpa ini,
/// keluar lalu masuk dengan akun lain di proses yang sama masih menampilkan
/// toko akun sebelumnya, dan setiap buka sesi di sana ditolak server.
final tokoListProvider = FutureProvider<List<Toko>>((ref) async {
  ref.watch(authControllerProvider.select((a) => a.valueOrNull?.id));
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

/// Manifest toko aktif — menentukan menu & alur yang tampil (papan pesanan
/// hanya untuk bidang usaha bertahap). Kosong bila toko belum dipilih atau
/// server belum menyediakan endpoint manifest.
final activeManifestProvider = FutureProvider<TokoManifest>((ref) async {
  final id = ref.watch(activeTokoIdProvider).valueOrNull;
  if (id == null || id.isEmpty) return const TokoManifest();
  final r = await ref.watch(tokoRepositoryProvider).manifest(id);
  return r.when(ok: (v) => v, err: (e) => throw e);
});

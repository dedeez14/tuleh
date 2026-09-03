import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../toko/presentation/providers/toko_providers.dart';
import '../../data/datasources/sesi_remote_datasource.dart';
import '../../data/repositories/sesi_repository_impl.dart';
import '../../domain/entities/sesi.dart';
import '../../domain/entities/sesi_rekap.dart';
import '../../domain/repositories/sesi_repository.dart';

final sesiRepositoryProvider = Provider<SesiRepository>(
  (ref) => SesiRepositoryImpl(SesiRemoteDataSource(ref.watch(dioProvider))),
);

/// Sesi kasir aktif — sumber kebenaran untuk gating checkout.
class ActiveSesiNotifier extends AsyncNotifier<Sesi?> {
  @override
  Future<Sesi?> build() async {
    ref.watch(activeTokoIdProvider); // sesi per toko → refresh saat ganti toko
    final result = await ref.watch(sesiRepositoryProvider).aktif();
    return result.when(ok: (s) => s, err: (e) => throw e);
  }

  /// Buka sesi (kas awal). Gudang diambil otomatis (gudang pertama toko).
  /// Lempar [ApiException] bila gagal (ditangani pemanggil).
  Future<void> buka(double kasAwal) async {
    final repo = ref.read(sesiRepositoryProvider);
    final gudang = (await repo.firstGudangId()).when(ok: (v) => v, err: (e) => throw e);
    if (gudang == null || gudang.isEmpty) {
      throw const ApiException(message: 'Gudang toko tidak ditemukan.');
    }
    (await repo.buka(kasAwal: kasAwal, gudangId: gudang)).when(ok: (_) {}, err: (e) => throw e);
    state = await AsyncValue.guard(
      () async => (await repo.aktif()).when(ok: (s) => s, err: (e) => throw e),
    );
  }

  /// Tutup sesi aktif dengan kas akhir fisik. Id diambil dari daftar (BUKA).
  Future<void> tutup({required double kasAkhirFisik, String? catatan}) async {
    final repo = ref.read(sesiRepositoryProvider);
    final id = (await repo.aktifId()).when(ok: (v) => v, err: (e) => throw e);
    if (id == null || id.isEmpty) {
      throw const ApiException(message: 'Sesi aktif tidak ditemukan.');
    }
    (await repo.tutup(id: id, kasAkhirFisik: kasAkhirFisik, catatan: catatan))
        .when(ok: (_) {}, err: (e) => throw e);
    state = const AsyncData(null);
  }
}

final activeSesiProvider =
    AsyncNotifierProvider<ActiveSesiNotifier, Sesi?>(ActiveSesiNotifier.new);

/// Rekap sesi aktif (kas & penjualan). Ikut menyegar saat sesi buka/tutup.
final sesiRekapProvider = FutureProvider<SesiRekap?>((ref) async {
  ref.watch(activeTokoIdProvider);
  ref.watch(activeSesiProvider);
  final r = await ref.watch(sesiRepositoryProvider).rekapAktif();
  return r.when(ok: (v) => v, err: (e) => throw e);
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/offline/antrean_tulis.dart';
import '../../../../core/offline/pengurai.dart';
import '../../../toko/presentation/providers/toko_providers.dart';
import '../../data/datasources/meja_remote_datasource.dart';
import '../../data/repositories/meja_offline_repository.dart';
import '../../domain/entities/bill_detail.dart';
import '../../domain/entities/meja.dart';
import '../../domain/repositories/meja_repository.dart';

/// Repositori bon meja dengan jalur offline (antrean) — lihat
/// [MejaOfflineRepository]. Saat online perilakunya sama dengan remote.
final mejaRepositoryProvider = Provider<MejaRepository>(
  (ref) => MejaOfflineRepository(
    remote: MejaRemoteDataSource(ref.watch(dioProvider)),
    antrean: ref.watch(antreanStoreProvider),
    tulis: ref.watch(antreanTulisProvider),
    tokoId: ref.watch(activeTokoIdProvider).valueOrNull,
  ),
);

/// Peta meja toko aktif (refetch saat toko berganti / antrean berubah).
final mejaPetaProvider = FutureProvider<List<Meja>>((ref) async {
  ref.watch(activeTokoIdProvider);
  ref.watch(antreanVersiProvider);
  final r = await ref.watch(mejaRepositoryProvider).peta();
  return r.when(ok: (v) => v, err: (e) => throw e);
});

/// Detail bon (by id) untuk layar detail meja; ronde tertunda ikut tampil.
final billDetailProvider = FutureProvider.family<BillDetail, String>((ref, billId) async {
  ref.watch(antreanVersiProvider);
  final r = await ref.watch(mejaRepositoryProvider).detail(billId);
  return r.when(ok: (v) => v, err: (e) => throw e);
});

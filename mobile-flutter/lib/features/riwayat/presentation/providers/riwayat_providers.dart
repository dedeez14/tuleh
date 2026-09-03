import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../toko/presentation/providers/toko_providers.dart';
import '../../data/datasources/riwayat_remote_datasource.dart';
import '../../data/repositories/riwayat_repository_impl.dart';
import '../../domain/entities/transaksi.dart';
import '../../domain/entities/transaksi_detail.dart';
import '../../domain/repositories/riwayat_repository.dart';

final riwayatRepositoryProvider = Provider<RiwayatRepository>(
  (ref) => RiwayatRepositoryImpl(RiwayatRemoteDataSource(ref.watch(dioProvider))),
);

/// Daftar transaksi toko aktif (refetch saat toko berganti).
final riwayatListProvider = FutureProvider<List<Transaksi>>((ref) async {
  ref.watch(activeTokoIdProvider);
  final result = await ref.watch(riwayatRepositoryProvider).list();
  return result.when(ok: (v) => v, err: (e) => throw e);
});

/// Detail satu transaksi (by id) untuk tampilan struk.
final transaksiDetailProvider =
    FutureProvider.family<TransaksiDetail, String>((ref, id) async {
  final result = await ref.watch(riwayatRepositoryProvider).detail(id);
  return result.when(ok: (v) => v, err: (e) => throw e);
});

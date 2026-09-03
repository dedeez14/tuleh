import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../toko/presentation/providers/toko_providers.dart';
import '../../data/datasources/pengeluaran_remote_datasource.dart';
import '../../data/repositories/pengeluaran_repository_impl.dart';
import '../../domain/entities/pengeluaran.dart';
import '../../domain/repositories/pengeluaran_repository.dart';

final pengeluaranRepositoryProvider = Provider<PengeluaranRepository>(
  (ref) =>
      PengeluaranRepositoryImpl(PengeluaranRemoteDataSource(ref.watch(dioProvider))),
);

/// Bulan aktif (YYYY-MM). Default bulan berjalan.
String bulanKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

final pengeluaranBulanProvider = StateProvider<String>((ref) => bulanKey(DateTime.now()));

final pengeluaranListProvider = FutureProvider<List<Pengeluaran>>((ref) async {
  ref.watch(activeTokoIdProvider);
  final bulan = ref.watch(pengeluaranBulanProvider);
  final r = await ref.watch(pengeluaranRepositoryProvider).list(bulan);
  return r.when(ok: (v) => v, err: (e) => throw e);
});

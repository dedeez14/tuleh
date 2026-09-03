import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../toko/presentation/providers/toko_providers.dart';
import '../../data/datasources/meja_remote_datasource.dart';
import '../../data/repositories/meja_repository_impl.dart';
import '../../domain/entities/bill_detail.dart';
import '../../domain/entities/meja.dart';
import '../../domain/repositories/meja_repository.dart';

final mejaRepositoryProvider = Provider<MejaRepository>(
  (ref) => MejaRepositoryImpl(MejaRemoteDataSource(ref.watch(dioProvider))),
);

/// Peta meja toko aktif (refetch saat toko berganti).
final mejaPetaProvider = FutureProvider<List<Meja>>((ref) async {
  ref.watch(activeTokoIdProvider);
  final r = await ref.watch(mejaRepositoryProvider).peta();
  return r.when(ok: (v) => v, err: (e) => throw e);
});

/// Detail bon (by id) untuk layar detail meja.
final billDetailProvider = FutureProvider.family<BillDetail, String>((ref, billId) async {
  final r = await ref.watch(mejaRepositoryProvider).detail(billId);
  return r.when(ok: (v) => v, err: (e) => throw e);
});

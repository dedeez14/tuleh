import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../toko/presentation/providers/toko_providers.dart';
import '../../data/datasources/pelanggan_remote_datasource.dart';
import '../../data/repositories/pelanggan_repository_impl.dart';
import '../../domain/entities/pelanggan.dart';
import '../../domain/repositories/pelanggan_repository.dart';

final pelangganRepositoryProvider = Provider<PelangganRepository>(
  (ref) => PelangganRepositoryImpl(PelangganRemoteDataSource(ref.watch(dioProvider))),
);

final pelangganListProvider = FutureProvider<List<Pelanggan>>((ref) async {
  ref.watch(activeTokoIdProvider);
  final r = await ref.watch(pelangganRepositoryProvider).list();
  return r.when(ok: (v) => v, err: (e) => throw e);
});
